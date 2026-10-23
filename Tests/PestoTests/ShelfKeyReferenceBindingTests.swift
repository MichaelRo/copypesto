// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import Testing
@testable import Pesto

/// Records which handler of a coordinator ran, by name, so a test can say which one a key is supposed to reach.
@MainActor
private final class HandlerLog {
    var fired: [String] = []

    func install(on coordinator: KeyNavCoordinator) {
        coordinator.onLeft = { self.fired.append("onLeft") }
        coordinator.onRight = { self.fired.append("onRight") }
        coordinator.onFirst = { self.fired.append("onFirst") }
        coordinator.onLast = { self.fired.append("onLast") }
        coordinator.onPage = { _ in self.fired.append("onPage") }
        coordinator.onEscape = { self.fired.append("onEscape") }
        coordinator.onReturn = { self.fired.append("onReturn") }
        coordinator.onSpace = { self.fired.append("onSpace") }
        coordinator.onDelete = { self.fired.append("onDelete") }
        coordinator.onSelectAll = { self.fired.append("onSelectAll") }
        coordinator.onReturnPlain = { self.fired.append("onReturnPlain") }
        coordinator.onReturnPlainFromSearch = { self.fired.append("onReturnPlainFromSearch") }
        coordinator.onPrevPinboard = { self.fired.append("onPrevPinboard") }
        coordinator.onNextPinboard = { self.fired.append("onNextPinboard") }
        coordinator.onOpenSettings = { self.fired.append("onOpenSettings") }
        coordinator.onNewCollection = { self.fired.append("onNewCollection") }
        coordinator.onPasteAllSelected = { self.fired.append("onPasteAllSelected") }
        coordinator.onPasteSelectedOneByOne = { self.fired.append("onPasteSelectedOneByOne") }
        coordinator.onUndo = { self.fired.append("onUndo") }
        coordinator.onRedo = { self.fired.append("onRedo") }
        coordinator.searchTextIsEmpty = { true }
        coordinator.onPasteNth = { _ in self.fired.append("onPasteNth") }
        coordinator.onShowActions = { self.fired.append("onShowActions") }
        coordinator.onCopy = { self.fired.append("onCopy") }
        coordinator.onAskFromSearch = { self.fired.append("onAskFromSearch") }
        coordinator.onShowHidden = { self.fired.append("onShowHidden") }
        coordinator.onSearch = { self.fired.append("onSearch") }
        coordinator.onSaveImage = {
            self.fired.append("onSaveImage")
            return true
        }
        coordinator.onQuickLook = { self.fired.append("onQuickLook") }
        coordinator.onFilterChipMove = { _ in
            self.fired.append("onFilterChipMove")
            return true
        }
    }
}

@Suite("Shelf key reference — every listed key reaches its handler")
@MainActor
struct ShelfKeyReferenceBindingTests {
    /// What each key of each listed entry is meant to do, in the entry's key-code order. A new entry needs a row here,
    /// which is the point: Settings cannot list a key whose handler nobody checked.
    private static let handlers: [String: [String]] = [
        "← → Move between clips": ["onLeft", "onRight"],
        "← → With ⌥, move a screenful of clips": ["onPage", "onPage"],
        "Page Up Page Down Move a screenful of clips": ["onPage", "onPage"],
        "Home End Jump to the first or last clip": ["onFirst", "onLast"],
        "Return Paste the focused clip (Paste One by One if several are selected)": ["onReturn"],
        "⇧ Return Paste the focused clip as plain text": ["onReturnPlain"],
        "Space Select the focused clip": ["onSpace"],
        "⌫ ⌦ Delete the selected clips, or the focused one": ["onDelete", "onDelete"],
        "Esc Go back one step: a prompt, Quick Look, the hover card or the selection, then the shelf": ["onEscape"],
        "Type Search your clips": [],
        "⌘ A Select every clip shown": ["onSelectAll"],
        "⌘ 1–9 Paste the clip in that position": ["onPasteNth"],
        "⌘ Return Ask Pesto about the search": ["onAskFromSearch"],
        "⌘ E Show or hide a covered clip (⌘Return does too)": ["onShowHidden", "onShowHidden"],
        "Tab In search, move through the filters": ["onFilterChipMove"],
        "⇧ Tab In search, move back through the filters": ["onFilterChipMove"],
        "↓ ↑ In search, move through the results": ["onRight", "onLeft"],
        "⌘ F Search": ["onSearch"],
        "⌘ K Open the focused clip's actions": ["onShowActions"],
        "⌘ C Copy the focused clip": ["onCopy"],
        "⌘ Y Quick Look the focused clip": ["onQuickLook"],
        "⌘ S Save the focused picture to Downloads": ["onSaveImage"],
        "⌘ [ ] Switch collections": ["onPrevPinboard", "onNextPinboard"],
        "⌘ N Add a collection": ["onNewCollection"],
        "⌘ P Paste the selected clips all at once": ["onPasteAllSelected"],
        "⇧ ⌘ P Paste the selected clips one by one": ["onPasteSelectedOneByOne"],
        "⌘ Z Undo the last delete or change": ["onUndo"],
        "⇧ ⌘ Z Redo what was undone": ["onRedo"],
        "⌘ , Open Settings": ["onOpenSettings"]
    ]

    private func modifiers(for entry: ShelfKey) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if entry.needsCommand { flags.insert(.command) }
        if entry.needsShift { flags.insert(.shift) }
        if entry.needsOption { flags.insert(.option) }
        return flags
    }

    private struct Rig {
        let coordinator: KeyNavCoordinator
        let log: HandlerLog
        let window: NSWindow
    }

    private func armed() -> Rig {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let coordinator = KeyNavCoordinator()
        coordinator.isOverlayVisible = true
        coordinator.hostWindow = window
        coordinator.cardSpan = 50
        let log = HandlerLog()
        log.install(on: coordinator)
        return Rig(coordinator: coordinator, log: log, window: window)
    }

    private func press(
        _ code: Int, characters: String = "", for entry: ShelfKey, in window: NSWindow
    ) throws
    -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers(for: entry), timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(code)
        ))
    }

    @Test("every listed entry has a row saying which handler it reaches")
    func everyEntryIsInTheTable() {
        let missing = ShelfKeyReference.entries.map(\.id).filter { Self.handlers[$0] == nil }
        let stale = Set(Self.handlers.keys).subtracting(ShelfKeyReference.entries.map(\.id))
        #expect(missing.isEmpty, "no expected handler for: \(missing)")
        #expect(stale.isEmpty, "rows for entries that no longer exist: \(stale)")
    }

    @Test("pressing each key Settings lists is consumed and runs the handler named for it")
    func everyListedKey_firesItsHandler() throws {
        let rig = armed()
        let (coordinator, log, window) = (rig.coordinator, rig.log, rig.window)
        for entry in ShelfKeyReference.entries {
            let expected = try #require(Self.handlers[entry.id], "\(entry.id) has no row")
            coordinator.isSearchActive = entry.requiresSearch
            for (index, code) in entry.keyCodes.enumerated() {
                log.fired = []
                let event = try press(code, for: entry, in: window)
                #expect(coordinator.handle(event) == nil, "\(entry.id): key code \(code) was not consumed")
                #expect(log.fired == [expected[index]], "\(entry.id): key code \(code) ran \(log.fired)")
            }
        }
    }

    @Test("a ⌘ key is matched by the character it prints, so another layout reaches the same handler")
    func everyCommandLetter_firesOnAnotherLayout() throws {
        let rig = armed()
        let (coordinator, log, window) = (rig.coordinator, rig.log, rig.window)
        let modifierSymbols: Set = ["⇧", "⌘", "⌥", "⌃"]
        for entry in ShelfKeyReference.entries where entry.needsCommand {
            let expected = try #require(Self.handlers[entry.id])
            let letters = entry.keys.filter { $0.count == 1 && !modifierSymbols.contains($0) && $0 != "1" }
            guard !letters.isEmpty, letters.count <= expected.count else { continue }
            coordinator.isSearchActive = entry.requiresSearch
            for (index, letter) in letters.enumerated() {
                log.fired = []
                // 200 is no key on any layout: only the printed character can identify the command.
                let event = try press(200, characters: letter.lowercased(), for: entry, in: window)
                #expect(coordinator.handle(event) == nil, "\(entry.id): '\(letter)' was not consumed")
                #expect(log.fired == [expected[index]], "\(entry.id): '\(letter)' ran \(log.fired)")
            }
        }
    }

    @Test("a screenful is the clips that fit the shelf, less one so the last one seen stays in view")
    func page_movesByWhatFits() throws {
        let rig = armed()
        let (coordinator, window) = (rig.coordinator, rig.window)
        var moved: [Int] = []
        coordinator.onPage = { moved.append($0) }
        let entry = try #require(ShelfKeyReference.entries.first { $0.keys.first == "Page Up" })

        _ = try coordinator.handle(press(121, for: entry, in: window))
        _ = try coordinator.handle(press(116, for: entry, in: window))

        #expect(moved == [3, -3], "a 200-point shelf of 50-point cards shows 4 cards, so a page is 3")
    }

    @Test("⇧Return in search pastes the focused result as plain text")
    func shiftReturnInSearch_pastesPlain() throws {
        let rig = armed()
        let (coordinator, log, window) = (rig.coordinator, rig.log, rig.window)
        coordinator.isSearchActive = true
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36
        ))

        _ = coordinator.handle(event)

        #expect(log.fired == ["onReturnPlainFromSearch"])
    }

    @Test("in a right-to-left layout the arrows follow what the row shows: ← goes forward, → goes back (D-08)")
    func rightToLeft_swapsTheArrows() throws {
        let rig = armed()
        rig.coordinator.usesRightToLeft = true
        let entry = try #require(ShelfKeyReference.entries.first { $0.keys == ["←", "→"] && !$0.needsOption })
        for (code, expected) in [(123, "onRight"), (124, "onLeft")] {
            rig.log.fired = []
            let event = try press(code, for: entry, in: rig.window)
            _ = rig.coordinator.handle(event)
            #expect(rig.log.fired == [expected], "key code \(code) ran \(rig.log.fired)")
        }
    }
}
