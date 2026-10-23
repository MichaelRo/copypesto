// SPDX-License-Identifier: MIT
import AppKit
import CoreGraphics
import os

/// The 3-tier paste strategy orchestrator. See ADR 0009.
///
/// Flow per paste:
///   1. Caller captured the return target via `FocusRestoration.capture()` before showing the overlay.
///   2. Caller writes the payload to `AppPasteboard.general`.
///   3. Caller hides the overlay panel.
///   4. Call `executePaste(...)` here.
///
/// `executePaste` activates the target, then tries Tier 1 (AX direct write, text only),
/// falling back to Tier 2 (CGEvent Cmd+V), then Tier 3 (toast). The caller observes the
/// returned `Outcome` to decide what (if anything) to surface to the user.
@MainActor
public final class PasteCoordinator {
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "PasteCoordinator")

    public enum Outcome: Sendable, Equatable {
        case writtenViaAccessibility // Tier 1
        case writtenViaKeystroke // Tier 2
        case requiresManualPaste // Tier 3 — show toast
    }

    public enum PayloadKind: Sendable, Equatable {
        case text(String)
        case richText(String) // RTF / RTFD / HTML — uses Tier 2 (⌘V) so target app receives formatting
        case nonText // image / file / etc. — Tier 1 doesn't apply
    }

    public let focusRestoration: FocusRestoration
    public let keystrokeSynthesizer: KeystrokeSynthesizer
    public let accessibilityWriter: AccessibilityWriter
    private let recorder: PasteRecorder?
    private let canPostKeystrokes: @Sendable () -> Bool

    public init(
        focusRestoration: FocusRestoration = FocusRestoration(),
        keystrokeSynthesizer: KeystrokeSynthesizer = KeystrokeSynthesizer(),
        accessibilityWriter: AccessibilityWriter = AccessibilityWriter(),
        recorder: PasteRecorder? = .current,
        canPostKeystrokes: @escaping @Sendable () -> Bool = {
            // Either signal is enough: only when both say no is the keystroke certain to be dropped.
            CGPreflightPostEventAccess() || AccessibilityAccess.isTrusted
        }
    ) {
        self.focusRestoration = focusRestoration
        self.keystrokeSynthesizer = keystrokeSynthesizer
        self.accessibilityWriter = accessibilityWriter
        self.recorder = recorder
        self.canPostKeystrokes = canPostKeystrokes
    }

    /// Pastes, then (for a snippet with `{{cursor}}`) moves the caret back over the text that followed it.
    public func executePaste(payload: PayloadKind, caretOffsetFromEnd: Int? = nil) async -> Outcome {
        let outcome = await paste(payload: payload, caretOffsetFromEnd: caretOffsetFromEnd)
        // Tier 1 (writtenViaAccessibility) positions the caret directly during AX insertion.
        // Synthesizing left arrows is only needed for Tier 2 (writtenViaKeystroke) where Cmd+V pasted to the end.
        guard recorder == nil, Self.shouldMoveCaret(
            outcome: outcome, offset: caretOffsetFromEnd, isCancelled: Task.isCancelled,
            targetIsFrontmost: focusRestoration.isTargetFrontmost, canPost: canPostKeystrokes()
        ), let offset = caretOffsetFromEnd else { return outcome }
        // Let the paste land first: Tier 2 returns before the target app has inserted the text.
        try? await Task.sleep(for: .milliseconds(150))
        if focusRestoration.isTargetFrontmost, !Task.isCancelled {
            try? keystrokeSynthesizer.synthesizeLeftArrows(count: offset)
        }
        return outcome
    }

    /// The caret is moved only after a paste that happened, into the app that received it, and never for a task that
    /// was cancelled (sleep, lock): the arrows would move the caret in whatever the person is doing by then.
    static func shouldMoveCaret(
        outcome: Outcome, offset: Int?, isCancelled: Bool, targetIsFrontmost: Bool, canPost: Bool
    )
    -> Bool {
        guard let offset, offset > 0 else { return false }
        return outcome == .writtenViaKeystroke && !isCancelled && targetIsFrontmost && canPost
    }

    private func paste(payload: PayloadKind, caretOffsetFromEnd: Int? = nil) async -> Outcome {
        let whole = PerfSignposts.paste.begin("coordinatorPaste")
        defer { whole.end() }
        if let recorder {
            recorder.record(payload)
            return .writtenViaAccessibility
        }
        let targetID = focusRestoration.capturedTarget?.bundleIdentifier ?? "nil"
        let captureAge = focusRestoration.captureTime.map { Date.now.timeIntervalSince($0) } ?? -1
        let ageStr = String(format: "%.2f", captureAge)
        Self.logger.notice(
            "[paste] execute target=\(targetID, privacy: .public) age=\(ageStr, privacy: .public)s"
        )
        let activation = PerfSignposts.paste.begin("activate")
        let activated = await focusRestoration.activate(timeout: .milliseconds(250))
        activation.end()
        // Abort if the task was cancelled while activate() was sleeping (e.g., AppDelegate
        // cancelled it on NSWorkspace.didWakeNotification). Without this guard, a pending
        // paste task that survived a sleep/wake cycle would fire into whatever text field
        // the user is currently in.
        guard !Task.isCancelled else {
            Self.logger.notice("[paste] cancelled after activate — likely post-sleep resume")
            return .requiresManualPaste
        }
        guard activated, let target = focusRestoration.capturedTarget else {
            Self.logger.notice("[paste] fallback: target did not activate in time")
            return .requiresManualPaste
        }

        // Tier 1: AX direct write — caret-aware, inserts at the selection point.
        // Short-circuit on success: Tier 2 (Cmd+V) would paste the clipboard content a
        // second time at the advanced cursor position, producing a double-insert "few lines
        // after the original cursor." Only fall through to Tier 2 when Tier 1 declines.
        if Self.usesDirectWrite(for: payload), case let .text(string) = payload {
            let writer = accessibilityWriter
            let pid = target.processIdentifier
            let offset = caretOffsetFromEnd
            // Off the main actor: an Accessibility call into an unresponsive app waits for its timeout.
            let axWrite = PerfSignposts.paste.begin("axWrite")
            let wrote = await Task.detached(priority: .userInitiated) {
                writer.write(text: string, to: pid, caretOffsetFromEnd: offset)
            }.value
            axWrite.end()
            if wrote {
                Self.logger.debug("Paste tier 1: AX direct write succeeded")
                return .writtenViaAccessibility
            }
            Self.logger.debug("Paste tier 1: AX direct write skipped/failed, falling through to Tier 2")
        }

        // Tier 2: CGEvent Cmd+V posted to the HID tap.
        // FocusRestoration.activate() waits until the system says the target has the keyboard, so the target window is
        // key by the time we reach here — the window server routes the event correctly (ADR 0009).
        // When triggered directly from a global shortcut like ⌃⌥⌘V or ⌃1–⌃9, the Carbon hotkey fires on key-down while
        // the person's fingers still hold Control, Option or Shift; wait briefly for those modifiers to clear so the
        // window server delivers ⌘V rather than ⌃⌥⌘V.
        _ = await Self.waitForConflictingModifiersRelease()
        let synthesizer = keystrokeSynthesizer
        let keystroke = PerfSignposts.paste.begin("commandV")
        defer { keystroke.end() }
        let outcome = Self.keystrokeTier(
            canPost: canPostKeystrokes(),
            targetIsFrontmost: focusRestoration.isTargetFrontmost,
            isCancelled: Task.isCancelled
        ) { try synthesizer.synthesizeCommandV() }
        if outcome == .requiresManualPaste {
            Self.logger.notice("[paste] tier 2 unavailable or failed; falling back to the manual-paste toast")
        }
        return outcome
    }

    private nonisolated static let conflictingModifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskShift]

    /// Waits until Control, Option, and Shift are no longer physically held down, or `timeout` elapses.
    /// Returns immediately with zero delay when none of those modifiers are held (e.g. Return or ⌘1–⌘9 from the shelf).
    nonisolated static func waitForConflictingModifiersRelease(
        timeout: Duration = .milliseconds(400),
        pollInterval: Duration = .milliseconds(5),
        heldModifiers: @Sendable () -> CGEventFlags = { CGEventSource.flagsState(.combinedSessionState) }
    ) async
        -> Bool
    {
        if heldModifiers().isDisjoint(with: conflictingModifiers) { return true }
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: pollInterval)
            if heldModifiers().isDisjoint(with: conflictingModifiers) { return true }
        }
        return heldModifiers().isDisjoint(with: conflictingModifiers)
    }

    /// Text longer than this is pasted with ⌘V: the target app inserts a directly written string on its own main
    /// thread, which took about a second for 5 MB (`make bench-latency paste`, large clip), while ⌘V hands it the
    /// pasteboard to read at its own pace.
    static let directWriteLimit = 200_000

    static func usesDirectWrite(for payload: PayloadKind) -> Bool {
        guard case let .text(string) = payload else { return false }
        return string.utf8.count <= directWriteLimit
    }

    /// Tier 2: post ⌘V, but only if macOS will deliver it. Without Accessibility permission the system silently
    /// drops synthetic key events, so reporting success would hide the toast and paste nothing.
    /// It is also only posted while the target still has the front: the keystroke goes to whatever is frontmost, and a
    /// switch during the settle delay would type the clip, possibly a secret, into another app.
    /// A task cancelled during the Accessibility attempt (sleep, lock or wake interrupts it) must not go on to type:
    /// the
    /// clip would land in whatever the person is doing by then.
    static func keystrokeTier(
        canPost: Bool,
        targetIsFrontmost: Bool,
        isCancelled: Bool = false,
        post: () throws -> Void
    )
    -> Outcome {
        guard canPost, targetIsFrontmost, !isCancelled else { return .requiresManualPaste }
        do {
            try post()
            return .writtenViaKeystroke
        } catch {
            return .requiresManualPaste
        }
    }
}
