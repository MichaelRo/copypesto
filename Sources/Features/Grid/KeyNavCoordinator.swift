// SPDX-License-Identifier: MIT
import AppKit
import PestoCore

final class KeyNavCoordinator {
    var isSearchActive = false
    var isOverlayVisible = false
    var isEditingCollection = false
    /// While the history is locked the grid must not act on any key (Return would paste a clip nobody can see).
    var isLocked = false
    /// While the shelf asks before deleting, Return answers yes and Escape no; no other key reaches the grid.
    var isConfirming = false
    /// The window this grid lives in. The monitor sees every key in the app, so keys typed anywhere else
    /// (Settings, a rename field) must pass through untouched.
    weak var hostWindow: NSWindow?

    var onLeft: (() -> Void)?
    var onRight: (() -> Void)?
    /// Page Up, Page Down and ⌥← ⌥→, in the grid: a screenful of clips, signed (negative is toward the first clip).
    var onPage: ((Int) -> Void)?
    /// True in a right-to-left layout, where the first clip is at the right: ← then moves toward the later clips.
    var usesRightToLeft = false
    /// The width one card takes in the row, spacing included; with the window's width it says how many clips a page is.
    var cardSpan: CGFloat = 0
    /// Home and End, in the grid: the first and the last clip.
    var onFirst: (() -> Void)?
    var onLast: (() -> Void)?
    var onEscape: (() -> Void)?
    /// ⌘W: the shelf is a panel with no close button, so AppKit has nothing to close and beeps; the shelf goes away.
    var onDismissShelf: (() -> Void)?
    var onReturn: (() -> Void)?
    var onSpace: (() -> Void)?
    var onCharacterTyped: ((String) -> Void)?
    var onEscapeFromSearch: (() -> Void)?
    var onPrevPinboard: (() -> Void)?
    var onNextPinboard: (() -> Void)?
    var onDelete: (() -> Void)?
    var onSelectAll: (() -> Void)?
    var onReturnFromSearch: (() -> Void)?
    /// ⇧Return in search: the focused result, pasted as plain text.
    var onReturnPlainFromSearch: (() -> Void)?
    /// Return on the lock screen, when no button has the focus: the same unlock the button offers.
    var onUnlock: (() -> Void)?
    /// Toolbar shortcuts: Settings, +, Paste All and Paste One by One are otherwise reachable only by mouse,
    /// since the monitor sees every key before the responder chain does. Handled here rather than left
    /// to the window's own key-view loop or `.keyboardShortcut`, both of which this monitor pre-empts.
    var onOpenSettings: (() -> Void)?
    var onNewCollection: (() -> Void)?
    var onPasteAllSelected: (() -> Void)?
    var onPasteSelectedOneByOne: (() -> Void)?
    /// ⌘Z and ⇧⌘Z undo and redo the last delete or edit. In search and in a text field the field's own undo wins.
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    /// Whether the search field holds no text; only then does ⌘Z in search undo the shelf's last action.
    var searchTextIsEmpty: (() -> Bool)?
    /// ⌘1 to ⌘9 paste the card in that position, the number printed in its footer.
    var onPasteNth: ((Int) -> Void)?
    /// ⌘K opens the focused card's actions, the menu a right-click shows.
    var onShowActions: (() -> Void)?
    var onCopy: (() -> Void)?
    var onAskFromSearch: (() -> Void)?
    /// ⌘Return outside search shows or hides the focused covered clip; inside search it asks Pesto.
    var onShowHidden: (() -> Void)?
    var onConfirm: (() -> Void)?
    var onCancelConfirmation: (() -> Void)?
    var onSearch: (() -> Void)?
    /// ⌘S: true when the focused clip was a picture and was saved; otherwise the key goes on to the field or the app.
    var onSaveImage: (() -> Bool)?
    /// ⌘Y: Quick Look for the focused clip. The key is always consumed; the grid decides whether anything opens.
    var onQuickLook: (() -> Void)?
    /// ⇧Return: paste the focused clip's text without formatting.
    var onReturnPlain: (() -> Void)?

    /// Tab (+1) and Shift-Tab (-1) in search walk the filter chips; false when there are none, so the key goes on.
    var onFilterChipMove: ((Int) -> Bool)?
    /// Return or Space while the keyboard is on a chip: toggles it. False when the keyboard is on the search field.
    var onFilterChipToggle: (() -> Bool)?
    /// Esc while the keyboard is on a chip: back to the search field. False when it is already there.
    var onFilterChipRelease: (() -> Bool)?

    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func stop() {
        guard let obs = monitor else { return }
        NSEvent.removeMonitor(obs)
        monitor = nil
    }

    /// `internal` (not `private`) so tests can drive it directly without a real event loop.
    func handle(_ event: NSEvent) -> NSEvent? {
        guard isOverlayVisible else { return event }
        guard let hostWindow, event.window === hostWindow else { return event }
        guard !isEditingCollection else { return event }
        let flags = event.modifierFlags.intersection([.command, .control])
        // Cmd+[ / Cmd+], and the toolbar shortcuts below, work even while search is active.
        if isLocked { return handleLocked(event) }
        if isConfirming { return handleConfirming(event) }
        if flags == .command, consumeCommandShortcut(event) { return nil }
        if isSearchActive {
            if flags == .command, searchTextIsEmpty?() == true, consumeHistoryCommand(event) { return nil }
            return handleSearchMode(event)
        }
        return handleGridMode(event, flags: flags)
    }

    @discardableResult
    private func consumeCommandShortcut(_ event: NSEvent) -> Bool {
        let characters = event.charactersIgnoringModifiers
        guard let command = ShelfCommand.resolve(
            characters: characters, keyCode: event.keyCode, shift: event.modifierFlags.contains(.shift)
        ) else { return false }
        switch command {
        // The shelf has no Save, so ⌘S on a clip that is not a picture is swallowed instead of beeping.
        case .saveImage:
            _ = onSaveImage?()
            return true
        case .selectAll, .undo, .redo: return false
        // In the search field ⌘C belongs to the field: it copies the text the person selected there.
        case .copy where isSearchActive: return false
        default:
            perform(command)
            return true
        }
    }

    private func perform(_ command: ShelfCommand) {
        if handleNavigationCommand(command) { return }
        switch command {
        case .pasteAll, .pasteOneByOne: pasteSelection(allAtOnce: command == .pasteAll)
        case .actions: onShowActions?()
        case .copy: onCopy?()
        case .returnKey:
            // ⌘Return asks Pesto while searching and shows a covered clip otherwise; Return alone pastes.
            if isSearchActive { onAskFromSearch?() } else { onShowHidden?() }
        case let .pasteNth(number): onPasteNth?(number)
        case .quickLook: onQuickLook?()
        case .showHidden: onShowHidden?()
        case .saveImage, .selectAll, .undo, .redo,
             .search, .previousCollection, .nextCollection, .settings, .newCollection: break
        }
    }

    private func handleNavigationCommand(_ command: ShelfCommand) -> Bool {
        switch command {
        case .search: onSearch?()
        case .previousCollection: onPrevPinboard?()
        case .nextCollection: onNextPinboard?()
        case .settings: onOpenSettings?()
        case .newCollection: onNewCollection?()
        default: return false
        }
        return true
    }

    private func pasteSelection(allAtOnce: Bool) {
        if allAtOnce { onPasteAllSelected?() } else { onPasteSelectedOneByOne?() }
    }

    private func handleConfirming(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case 53:
            onCancelConfirmation?()
            return nil
        case 36, 76:
            guard !controlHasFocus(event) else { return event }
            onConfirm?()
            return nil
        case 48:
            return event
        case 49 where controlHasFocus(event):
            return event
        default:
            return nil
        }
    }

    private func handleLocked(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case 53:
            onEscape?()
            return nil
        case 48:
            return event
        case 36 where !controlHasFocus(event), 49 where !controlHasFocus(event):
            if event.keyCode == 36 { onUnlock?() }
            return nil
        case 36, 49:
            return event
        default:
            return nil
        }
    }

    private func handleActivationKey(_ event: NSEvent) -> NSEvent? {
        guard !controlHasFocus(event) else { return event }
        if event.keyCode == 36 {
            if event.modifierFlags.contains(.shift) { onReturnPlain?() } else { onReturn?() }
        } else {
            onSpace?()
        }
        return nil
    }

    private func controlHasFocus(_ event: NSEvent) -> Bool {
        nonisolated(unsafe) let event = event
        return MainActor.assumeIsolated {
            switch event.window?.firstResponder {
            case is NSControl, is NSText: true
            default: false
            }
        }
    }

    private func handleSearchMode(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case 48: // Tab, Shift-Tab: through the filter chips
            let backwards = event.modifierFlags.contains(.shift)
            return onFilterChipMove?(backwards ? -1 : 1) == true ? nil : event
        case 49 where onFilterChipToggle?() == true: // Space on a chip
            return nil
        case 53:
            if onFilterChipRelease?() == true { return nil }
            onEscapeFromSearch?()
            return nil
        case 125: // ↓
            onRight?()
            return nil
        case 126: // ↑
            onLeft?()
            return nil
        case 116, 121: // Page Up, Page Down: a one-line field has no page, and AppKit beeps
            return nil
        case 36:
            if onFilterChipToggle?() == true { return nil }
            if event.modifierFlags.contains(.shift) {
                onReturnPlainFromSearch?()
            } else {
                onReturnFromSearch?()
            }
            return event
        case 29 where event.modifierFlags.contains(.command): // ⌘0 owns nothing
            return nil
        default:
            return event
        }
    }

    /// ⌘Q and ⌘M belong to the app and the system (⌘W and ⌘H dismiss the shelf in the grid); every other ⌘ or ⌃ key the
    /// grid does not own is swallowed,
    /// because AppKit beeps for a key nothing takes (A-05).
    private func swallowsUnownedKey(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        guard !flags.isEmpty else { return false }
        let appCommands: Set<UInt16> = [12, 13, 4, 46, 50] // Q W H M `
        return !(flags == .command && appCommands.contains(event.keyCode))
    }

    private func handleGridMode(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> NSEvent? {
        nonisolated(unsafe) let unsafeEvent = event
        if MainActor.assumeIsolated({ unsafeEvent.window?.firstResponder is NSText }) { return event }
        if flags == .command, consumeGridCommand(event) { return nil }
        if let forward = pagingDirection(of: event) {
            page(forward: forward)
            return nil
        }
        switch event.keyCode {
        case 123, 124, 115, 119: // ← → Home End
            moveFocus(keyCode: event.keyCode)
            return nil
        case 125, 126: // ↓ ↑
            return nil
        case 48: // Tab
            return event
        case 53: // Escape
            onEscape?()
            return nil
        case 36, 49: // Return, Space
            return handleActivationKey(event)
        case 51, 117: // ⌫ backspace / ⌦ forward-delete
            onDelete?()
            return nil
        default:
            guard flags.isEmpty else { return swallowsUnownedKey(event, flags: flags) ? nil : event }
            guard let chars = event.characters,
                  !chars.isEmpty,
                  chars.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value < 0xF700 }) else { return nil }
            onCharacterTyped?(chars)
            return nil
        }
    }

    /// ⌘A, ⌘Z and ⇧⌘Z, which only the grid takes: a search field keeps them for its text.
    private func consumeGridCommand(_ event: NSEvent) -> Bool {
        if event.keyCode == 13, let onDismissShelf {
            onDismissShelf()
            return true
        }
        // ⌘H hides an app; Pesto is not the active app and has nothing to hide, so the key is taken without a beep.
        if event.keyCode == 4, onDismissShelf != nil { return true }
        if consumeHistoryCommand(event) { return true }
        guard ShelfCommand.resolve(
            characters: event.charactersIgnoringModifiers, keyCode: event.keyCode,
            shift: event.modifierFlags.contains(.shift)
        ) == .selectAll else { return false }
        onSelectAll?()
        return true
    }

    /// ⌘Z and ⇧⌘Z. In an empty search field there is no text to undo, so they reach the shelf.
    private func consumeHistoryCommand(_ event: NSEvent) -> Bool {
        switch ShelfCommand.resolve(
            characters: event.charactersIgnoringModifiers, keyCode: event.keyCode,
            shift: event.modifierFlags.contains(.shift)
        ) {
        case .undo: onUndo?()
        case .redo: onRedo?()
        default: return false
        }
        return true
    }

    /// Page Down and the ⌥ arrow that points toward the later clips page forward, Page Up and the other arrow back; nil
    /// for any other key. In a right-to-left layout the later clips are to the left.
    private func pagingDirection(of event: NSEvent) -> Bool? {
        switch event.keyCode {
        case 121: return true
        case 116: return false
        case 123, 124:
            guard event.modifierFlags.contains(.option) else { return nil }
            return (event.keyCode == 124) != usesRightToLeft
        default: return nil
        }
    }

    /// The clips that fit the window, less one so the last clip seen stays in view; at least one.
    private func page(forward: Bool) {
        let window = hostWindow
        let width = MainActor.assumeIsolated { window?.frame.width ?? 0 }
        let fitting = cardSpan > 0 ? Int(width / cardSpan) : 0
        let size = max(1, fitting - 1)
        onPage?(forward ? size : -size)
    }

    private func moveFocus(keyCode: UInt16) {
        switch keyCode {
        case 123: (usesRightToLeft ? onRight : onLeft)?()
        case 124: (usesRightToLeft ? onLeft : onRight)?()
        case 115: onFirst?()
        default: onLast?()
        }
    }
}
