// SPDX-License-Identifier: MIT
import AppKit
import ApplicationServices
import os

public protocol EventPosting: Sendable {
    func post(_ event: CGEvent)
}

public struct HIDEventPoster: EventPosting {
    public init() {}

    public func post(_ event: CGEvent) {
        event.post(tap: .cghidEventTap)
    }
}

/// Tier 2 of the paste strategy: synthesize a Cmd+V via CGEvent. See ADR 0009.
///
/// Requires Accessibility permission (`AccessibilityAccess.isTrusted`). The caller is
/// responsible for verifying that the target app has been activated before invoking.
public struct KeystrokeSynthesizer: Sendable {
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "KeystrokeSynthesizer")

    private let poster: any EventPosting
    private let keyCodeForV: @Sendable () -> CGKeyCode

    public init(
        poster: any EventPosting = HIDEventPoster(),
        keyCodeForV: @escaping @Sendable () -> CGKeyCode = {
            KeyboardLayoutKeyCode.current(for: "v") ?? KeystrokeSynthesizer.ansiKeyCodeForV
        }
    ) {
        self.poster = poster
        self.keyCodeForV = keyCodeForV
    }

    public enum Error: Swift.Error, Equatable, Sendable {
        case eventCreationFailed
    }

    /// The `V` position on an ANSI layout, used only when the current layout cannot be read.
    public static let ansiKeyCodeForV: CGKeyCode = 0x09

    public var hasAccessibility: Bool {
        AccessibilityAccess.isTrusted
    }

    /// Synthesizes a Cmd+V keystroke via CGEvent posted to the HID event tap.
    ///
    /// After the overlay is ordered out and `FocusRestoration.activate()` has waited until the system says the target
    /// has
    /// the keyboard (ADR 0009), the target app's window is key again. `.cghidEventTap` routes through the window
    /// server's normal key-window dispatch, so the event lands in the correct text field, but only
    /// if Accessibility permission is granted: otherwise macOS drops it silently (see
    /// `PasteCoordinator.keystrokeTier`, which checks first).
    public func synthesizeCommandV() throws {
        let source = CGEventSource(stateID: .privateState)
        let keyCode = keyCodeForV()
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else
        {
            throw Error.eventCreationFailed
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        poster.post(down)
        poster.post(up)
        Self.logger.debug("Paste tier 2: CGEvent Cmd+V posted to HID tap")
    }

    /// The most left arrows a paste posts to put the caret at `{{cursor}}`; a longer tail leaves the caret at the end.
    public static let maxCaretMoves = 400
    private static let leftArrowKeyCode: CGKeyCode = 0x7B

    /// Presses ← `count` times, to move the caret back from the end of what was just pasted.
    public func synthesizeLeftArrows(count: Int) throws {
        guard count > 0 else { return }
        let source = CGEventSource(stateID: .privateState)
        let key = Self.leftArrowKeyCode
        for _ in 0..<min(count, Self.maxCaretMoves) {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else
            {
                throw Error.eventCreationFailed
            }
            down.flags = []
            up.flags = []
            poster.post(down)
            poster.post(up)
        }
    }
}
