// SPDX-License-Identifier: MIT
import Foundation

/// Why the shelf is closing, decided by whoever closes it and acted on once, when the hide has happened. It replaces
/// three loose fields (a pending paste, a pending action and a running stack) that the hide handler read in a fixed
/// order
/// to guess what the close meant, and that a second close in a row could clear before they were used
/// (`AppState.close`).
public enum ShelfExit {
    /// Escape, a click outside or the shortcut again: nothing is pasted.
    case dismissed
    /// A clip was chosen. The paste runs in the hide animation's completion (ADR 0009), after the target has the
    /// keyboard.
    case paste(ClipboardItem, PasteCoordinator.PayloadKind)
    /// Something that has to happen once the shelf is gone, such as opening Settings.
    case afterHide(@MainActor () -> Void)
    /// A stack was just started: its first clip is pasted and its progress panel opens.
    case startStack

    /// What the hide handler does, apart from hiding the panel.
    public enum Plan: Equatable, Sendable {
        case nothing
        case pasteChosenClip
        case runAfterHide
        case startStack
    }

    public var plan: Plan {
        switch self {
        case .dismissed: .nothing
        case .paste: .pasteChosenClip
        case .afterHide: .runAfterHide
        case .startStack: .startStack
        }
    }

    /// Whether closing with this exit does anything when the shelf is already closed. A dismissal does not: a second
    /// `false` would only run the hide handler again, and could clear an exit that was about to be used.
    public var actsWhenAlreadyClosed: Bool {
        if case .dismissed = self { return false }
        return true
    }
}
