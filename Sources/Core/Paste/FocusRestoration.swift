// SPDX-License-Identifier: MIT
import AppKit
import ApplicationServices
import os

/// Captures the frontmost application at overlay-open time and restores it on paste.
/// MUST be called before the overlay panel is shown — once we show, *we* are frontmost.
@MainActor
public final class FocusRestoration {
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "FocusRestoration")
    /// Maximum time between capture() and activate() before we treat the capture as stale.
    /// Covers screen-lock/unlock and other scenarios where Task.sleep resumes long after intended.
    private static let captureDeadline: TimeInterval = 15
    /// The activation notification fires before the target's key window is ready to take a keystroke.
    private static let notificationPathSettle: Duration = .milliseconds(200)

    public private(set) var capturedTarget: NSRunningApplication?
    public private(set) var captureTime: Date?

    private let frontmostApplication: @MainActor () -> NSRunningApplication?
    private let workspaceCenter: NotificationCenter
    private let now: @Sendable () -> Date
    private let ownProcessIdentifier: pid_t
    private let focusProbe: any KeyboardFocusProbing
    private let pollInterval: Duration

    public init(
        frontmostApplication: @escaping @MainActor ()
            -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication },
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        now: @escaping @Sendable () -> Date = { .now },
        ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        focusProbe: any KeyboardFocusProbing = SystemKeyboardFocusProbe(),
        pollInterval: Duration = .milliseconds(5)
    ) {
        self.focusProbe = focusProbe
        self.pollInterval = pollInterval
        self.ownProcessIdentifier = ownProcessIdentifier
        self.frontmostApplication = frontmostApplication
        self.workspaceCenter = workspaceCenter
        self.now = now
    }

    /// The name of the app being pasted into, for `{{app}}`.
    public var targetName: String {
        capturedTarget?.localizedName ?? ""
    }

    /// Pesto is never the target: a paste into Pesto's own window would land in Pesto's own field.
    public func capture() {
        let front = frontmostApplication()
        guard front?.processIdentifier != ownProcessIdentifier else {
            clear()
            return
        }
        capturedTarget = front
        captureTime = now()
    }

    /// For a paste started from a window of Pesto's own that never took the app forward (the AI answer): the app the
    /// person was in is still the target, and Pesto being in front keeps the earlier capture instead of dropping it.
    public func captureKeepingTargetWhenPestoIsFront() {
        if frontmostApplication()?.processIdentifier == ownProcessIdentifier {
            markHidden()
        } else {
            capture()
        }
    }

    /// The deadline measures how long ago the shelf let go of the screen, not how long a person spent in it.
    public func markHidden() {
        guard let target = capturedTarget, !target.isTerminated else { return }
        captureTime = now()
    }

    var isStale: Bool {
        guard let captureTime else { return false }
        return now().timeIntervalSince(captureTime) > Self.captureDeadline
    }

    var isTargetFrontmost: Bool {
        guard let target = capturedTarget else { return false }
        return frontmostApplication()?.processIdentifier == target.processIdentifier
    }

    public func clear() {
        capturedTarget = nil
        captureTime = nil
    }

    /// Activate the captured target and wait up to `timeout` for the activation to be confirmed.
    /// Returns true iff activation completed within the budget.
    public func activate(timeout: Duration = .milliseconds(250)) async -> Bool {
        guard let target = capturedTarget else { return false }
        if isStale, let t = captureTime {
            let age = now().timeIntervalSince(t)
            Self.logger.warning("FocusRestoration: activate skipped — capture is \(age, privacy: .public)s stale")
            capturedTarget = nil
            captureTime = nil
            return false
        }

        // Restore focus to the target app. Two-pronged approach:
        //
        // 1. NSRunningApplication.activate() — macOS 14+ API that does NOT require the caller
        //    to be frontmost. This is the primary mechanism and works without AX permission.
        //    The deprecated activate(options: .activateIgnoringOtherApps) is silently ignored
        //    on macOS 14+ when linked against the new SDK, so it must not be used here.
        //
        // 2. AX kAXFrontmostAttribute — belt-and-suspenders when AX is granted. Bypasses the
        //    window server directly so the target's key window is restored faster.
        Self.logger.info("FocusRestoration: activating \(target.bundleIdentifier ?? "unknown", privacy: .public)")
        // Subscribe before activating: an activation that completes first would otherwise be missed.
        let confirmation = makeActivationConfirmation(pid: target.processIdentifier)

        if #available(macOS 14, *) {
            _ = target.activate()
        } else {
            target.activate(options: .activateIgnoringOtherApps)
        }
        let pid = target.processIdentifier
        let frontmostRequest = PerfSignposts.paste.begin("axSetFrontmost")
        let axResult = await Task.detached(priority: .userInitiated) { Self.setFrontmost(pid) }.value
        frontmostRequest.end()
        Self.logger.info("FocusRestoration: AX kAXFrontmostAttribute set, result=\(axResult.rawValue)")

        if isTargetFrontmost {
            confirmation.cancel()
            // Target is already frontmost (always true for .accessory apps). The overlay panel
            // uses makeKeyAndOrderFront so it can become the key window when the search field is
            // focused. After orderOut(nil), the window server completes the cross-process key-window
            // handoff back to the target some time later; a CGEvent Cmd+V that arrives before it is
            // silently dropped — the pasteboard has the content but the event goes nowhere. The system says
            // when the target has the keyboard (`KeyboardFocusProbing`); 500 ms is only the ceiling, and what
            // is waited out when the system will not say (no Accessibility permission).
            let settle = PerfSignposts.paste.begin("settleAlreadyFrontmost")
            await waitForKeyboardFocus(of: target.processIdentifier, ceiling: .milliseconds(500))
            settle.end()
            guard !Task.isCancelled else {
                Self.logger
                    .info("FocusRestoration: activate cancelled while waiting for the keyboard (likely post-wake)")
                return false
            }
            Self.logger.info("FocusRestoration: already-frontmost path, the target has the keyboard")
            return true
        }

        let wait = PerfSignposts.paste.begin("awaitActivation")
        defer { wait.end() }
        return await awaitActivation(confirmation: confirmation, pid: target.processIdentifier, timeout: timeout)
    }

    /// Runs off the main actor and with a short messaging timeout, so a hung app cannot freeze Pesto's own window.
    private nonisolated static func setFrontmost(_ pid: pid_t) -> AXError {
        let app = AXUIElementCreateApplication(pid)
        AccessibilityTimeout.apply(to: app)
        return AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, true as CFTypeRef)
    }

    /// Returns once the system reports `pid` as the process with the keyboard, or when `ceiling` has passed, or when
    /// the
    /// task is cancelled. The probe runs off the main actor: an Accessibility call can wait for its timeout.
    func waitForKeyboardFocus(of pid: pid_t, ceiling: Duration) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: ceiling)
        let probe = focusProbe
        while !Task.isCancelled, clock.now < deadline {
            let focused = await Task.detached(priority: .userInitiated) { probe.focusedProcess() }.value
            if focused == pid { return }
            try? await Task.sleep(for: pollInterval)
        }
    }

    /// Subscribes before the activation is requested, so an activation that completes first is not missed. Workspace
    /// notifications are posted to the workspace's own center, not `NotificationCenter.default`.
    func makeActivationConfirmation(pid: pid_t) -> Task<Bool, Never> {
        let stream = workspaceCenter.notifications(named: NSWorkspace.didActivateApplicationNotification)
        return Task<Bool, Never> {
            for await note in stream {
                if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   app.processIdentifier == pid
                {
                    return true
                }
            }
            return false
        }
    }

    func awaitActivation(confirmation: Task<Bool, Never>, pid: pid_t, timeout: Duration) async -> Bool {
        let timeoutTask = Task<Bool, Never> {
            try? await Task.sleep(for: timeout)
            return false
        }

        return await withTaskCancellationHandler {
            await withTaskGroup(of: Bool.self) { group in
                group.addTask { await confirmation.value }
                group.addTask { await timeoutTask.value }
                let result = await group.next() ?? false
                if result { await waitForKeyboardFocus(of: pid, ceiling: Self.notificationPathSettle) }
                // Cancel both underlying tasks explicitly. group.cancelAll() cancels the
                // task-group child wrappers but NOT the confirmation/timeoutTask objects
                // themselves — without this, confirmation leaks and keeps listening for
                // didActivateApplicationNotification indefinitely.
                confirmation.cancel()
                timeoutTask.cancel()
                group.cancelAll()
                // The target may have come forward just after the wait ran out.
                return result || frontmostApplication()?.processIdentifier == pid
            }
        } onCancel: {
            confirmation.cancel()
            timeoutTask.cancel()
        }
    }
}
