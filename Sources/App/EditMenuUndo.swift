// SPDX-License-Identifier: MIT
import AppKit
import PestoCore

/// The Edit menu's Undo and Redo. A text field being edited keeps its own text undo; otherwise they undo and redo the
/// last delete or change to a clip or collection (ADR 0008), named in the title ("Undo Delete 3 Clips"). The shelf is a
/// panel that never becomes key, so its own keys are handled by `KeyNavCoordinator`; this is for the Settings window.
@MainActor
final class EditMenuUndo: NSObject, NSMenuItemValidation {
    private weak var appState: AppState?

    private(set) lazy var undoItem = makeItem(title: "Undo", action: #selector(undo(_:)), key: "z", flags: .command)
    private(set) lazy var redoItem = makeItem(
        title: "Redo", action: #selector(redo(_:)), key: "z", flags: [.command, .shift]
    )

    init(appState: AppState) {
        self.appState = appState
    }

    private func makeItem(title: String.LocalizationValue, action: Selector, key: String, flags: NSEvent.ModifierFlags)
    -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: title), action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = flags
        item.target = self
        return item
    }

    /// The text being edited in the key window, which owns ⌘Z while the cursor is in it.
    private var textUndoManager: UndoManager? {
        (NSApp.keyWindow?.firstResponder as? NSText)?.undoManager
    }

    @objc
    private func undo(_: Any?) {
        if let manager = textUndoManager { manager.undo() } else { appState?.performUndo() }
    }

    @objc
    private func redo(_: Any?) {
        if let manager = textUndoManager { manager.redo() } else { appState?.performRedo() }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let isRedo = item === redoItem
        if let manager = textUndoManager {
            item.title = isRedo ? String(localized: "Redo") : String(localized: "Undo")
            return isRedo ? manager.canRedo : manager.canUndo
        }
        guard let appState, !appState.isHistoryLocked, let history = appState.undoHistory else {
            item.title = isRedo ? String(localized: "Redo") : String(localized: "Undo")
            return false
        }
        let label = isRedo ? history.redoLabel : history.undoLabel
        item.title = isRedo ? UndoText.menuTitle(redo: label) : UndoText.menuTitle(undo: label)
        return label != nil
    }
}
