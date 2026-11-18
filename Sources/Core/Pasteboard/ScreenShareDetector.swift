// SPDX-License-Identifier: MIT
#if os(macOS)
import AppKit
import CoreGraphics

/// Polls every 3 seconds for active screen mirroring, known screen-sharing processes or a browser's sharing bar, only
/// while the
/// "hide contents during screen sharing" setting is on, and reports changes only.
/// Call `start()` once and observe `onStateChange` to receive updates on the main actor.
@MainActor
public final class ScreenShareDetector {
    /// Known screen-sharing / recording app bundle IDs, lowercased: bundle IDs are compared without regard to case.
    private nonisolated static let sharingBundleIDs: Set<String> = [
        "com.apple.screensharing",
        "us.zoom.xos",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.webex.meetingmanager",
        "com.loom.desktop",
        "com.obsproject.obs-studio",
        "com.apple.facetime",
        "com.hnc.discord"
    ]

    /// Called on the main actor whenever the detected state changes.
    public var onStateChange: ((Bool) -> Void)?

    private var pollingTask: Task<Void, Never>?
    private var tracker = SharingStateTracker()
    private let isMirroredProbe: @MainActor () -> Bool
    private let runningBundleIDsProbe: @MainActor () -> Set<String>
    private let windowSnapshotsProbe: @MainActor () -> [WindowSnapshot]
    private let bundleIDForPIDProbe: @MainActor (Int32) -> String?

    public init(
        isMirrored: (@MainActor () -> Bool)? = nil,
        runningBundleIDs: (@MainActor () -> Set<String>)? = nil,
        windowSnapshots: (@MainActor () -> [WindowSnapshot])? = nil,
        bundleIDForPID: (@MainActor (Int32) -> String?)? = nil
    ) {
        self.isMirroredProbe = isMirrored ?? { ScreenShareDetector.isMirrored() }
        self.runningBundleIDsProbe = runningBundleIDs ?? {
            Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        }
        self.windowSnapshotsProbe = windowSnapshots ?? { BrowserShareSignature.onScreenWindows() }
        self.bundleIDForPIDProbe = bundleIDForPID ?? {
            NSRunningApplication(processIdentifier: $0)?.bundleIdentifier
        }
    }

    public var isRunning: Bool {
        pollingTask != nil
    }

    public func start() {
        pollingTask?.cancel()
        tracker = SharingStateTracker()
        // Runs on the main actor: NSWorkspace is main-actor-isolated and the display check is cheap.
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.pollOnce()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    public func pollOnce() {
        let sharing = isMirroredProbe()
            || Self.isSharing(runningBundleIDs: runningBundleIDsProbe())
            || BrowserShareSignature.isSharing(windows: windowSnapshotsProbe(), bundleID: bundleIDForPIDProbe)
        publish(sharing)
    }

    private func publish(_ sharing: Bool) {
        if let changed = tracker.update(sharing) { onStateChange?(changed) }
    }

    public func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        if tracker.update(false) == false { onStateChange?(false) }
    }

    // MARK: - Detection logic

    /// Safe to call from any context — delegates NSWorkspace access to the main actor internally.
    public nonisolated static func detect() -> Bool {
        isMirrored() // hasSharingProcess requires MainActor; use start() for async polling
    }

    private nonisolated static func isMirrored() -> Bool {
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        guard displayCount > 0 else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &displays, &displayCount)
        return displays.contains { CGDisplayMirrorsDisplay($0) != kCGNullDirectDisplay }
    }

    public nonisolated static func isSharing(runningBundleIDs: Set<String>) -> Bool {
        !sharingBundleIDs.isDisjoint(with: Set(runningBundleIDs.map { $0.lowercased() }))
    }
}
#endif
