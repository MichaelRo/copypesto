// SPDX-License-Identifier: MIT
import AppKit

/// What a running paste stack needs from the system (ADR 0009): a watch for the person's own ⌘V, which pastes the clip
/// Pesto made ready, and the short wait before the next clip is made ready (the app has to read the pasteboard for the
/// paste that just happened first). The stack itself is `AppState.activeStack`.
@MainActor
public final class StackPasteSession {
    public init() {}

    public private(set) var isWatching = false
    private var monitor: Any?
    private var ownPasteUntil = Date.distantPast
    private var preparing: Task<Void, Never>?

    /// The ⌘V Pesto posts itself to paste the first clip must not be counted as the person's.
    public func ignoreOwnPaste(for seconds: TimeInterval = 1.5) {
        ownPasteUntil = Date.now.addingTimeInterval(seconds)
    }

    private var ownPasteInFlight: Bool {
        Date.now < ownPasteUntil
    }

    /// Watches for ⌘V in every app. A launch that uses no system integrations (a test) only records that it is
    /// watching, so a test can drive the stack without a real keystroke.
    public func watch(onUserPaste: @escaping @MainActor () -> Void) {
        guard !isWatching else { return }
        isWatching = true
        guard LaunchMode.current.usesSystemIntegrations else { return }
        let pasteKey = UInt16(KeyboardLayoutKeyCode.current(for: "v") ?? KeystrokeSynthesizer.ansiKeyCodeForV)
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let (code, modifiers) = (event.keyCode, event.modifierFlags)
            Task { @MainActor [weak self] in
                guard let self else { return }
                if StackKeyPolicy.isUserPaste(
                    keyCode: code, modifiers: modifiers, pasteKeyCode: pasteKey, ownPasteInFlight: ownPasteInFlight
                ) { onUserPaste() }
            }
        }
    }

    public func prepare(after delay: Duration = .milliseconds(300), _ work: @escaping @MainActor () -> Void) {
        preparing?.cancel()
        preparing = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            work()
        }
    }

    public func stop() {
        preparing?.cancel()
        preparing = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isWatching = false
    }
}
