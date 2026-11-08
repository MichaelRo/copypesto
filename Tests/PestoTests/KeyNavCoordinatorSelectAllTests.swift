// SPDX-License-Identifier: MIT
import AppKit
import Testing
@testable import Pesto

@Suite("KeyNavCoordinator — Edit shortcuts in the search field")
@MainActor
struct KeyNavCoordinatorSelectAllTests {
    private let window: NSWindow = {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }()

    private final class SpyFieldEditor: NSTextView {
        var calls: [String] = []
        let history = UndoManager()
        override var undoManager: UndoManager? {
            history
        }

        override func copy(_: Any?) {
            calls.append("copy")
        }

        override func cut(_: Any?) {
            calls.append("cut")
        }

        override func paste(_: Any?) {
            calls.append("paste")
        }
    }

    private func makeFixture(text: String = "invoice") -> (KeyNavCoordinator, SpyFieldEditor) {
        let editor = SpyFieldEditor(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        editor.string = text
        window.contentView?.addSubview(editor)
        #expect(window.makeFirstResponder(editor))
        let coordinator = KeyNavCoordinator()
        coordinator.isOverlayVisible = true
        coordinator.hostWindow = window
        coordinator.isSearchActive = true
        return (coordinator, editor)
    }

    private func command(_ key: String, keyCode: UInt16, shift: Bool = false) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: shift ? [.command, .shift] : .command, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: key,
            charactersIgnoringModifiers: key, isARepeat: false, keyCode: keyCode
        ))
    }

    @Test("⌘A in the search field selects the field's text, not the clips")
    func whenSearchFieldHasFocus_thenCommandASelectsItsText() throws {
        let (coordinator, editor) = makeFixture()
        var selectedClips = false
        coordinator.onSelectAll = { selectedClips = true }

        let result = try coordinator.handle(command("a", keyCode: 0))

        #expect(result == nil, "the shelf panel has no Edit menu to take ⌘A, so the monitor must consume it")
        #expect(editor.selectedRange() == NSRange(location: 0, length: 7))
        #expect(!selectedClips)
    }

    @Test("a second ⌘A, with all the text already selected, selects the clips shown")
    func whenAllTextIsSelected_thenCommandASelectsTheClips() throws {
        let (coordinator, editor) = makeFixture()
        editor.setSelectedRange(NSRange(location: 0, length: 7))
        var selectedClips = false
        coordinator.onSelectAll = { selectedClips = true }

        let result = try coordinator.handle(command("a", keyCode: 0))

        #expect(result == nil)
        #expect(selectedClips)
    }

    @Test("⌘A in an empty search field selects the clips shown")
    func whenFieldIsEmpty_thenCommandASelectsTheClips() throws {
        let (coordinator, _) = makeFixture(text: "")
        var selectedClips = false
        coordinator.onSelectAll = { selectedClips = true }

        #expect(try coordinator.handle(command("a", keyCode: 0)) == nil)

        #expect(selectedClips)
    }

    @Test("⌘X, ⌘C and ⌘V go to the field editor and are consumed")
    func whenSearchFieldHasFocus_thenCutCopyPasteReachTheField() throws {
        let (coordinator, editor) = makeFixture()
        var shelfCopied = false
        coordinator.onCopy = { shelfCopied = true }

        for (key, code) in [("x", UInt16(7)), ("c", 8), ("v", 9)] {
            #expect(try coordinator.handle(command(key, keyCode: code)) == nil)
        }

        #expect(editor.calls == ["cut", "copy", "paste"])
        #expect(!shelfCopied)
    }

    @Test("⌘Z and ⇧⌘Z undo and redo in a search field that has text")
    func whenFieldHasText_thenUndoRedoGoToTheFieldsOwnHistory() throws {
        let (coordinator, editor) = makeFixture()
        var undone = 0
        var shelfUndone = false
        coordinator.onUndo = { shelfUndone = true }
        coordinator.searchTextIsEmpty = { false }
        editor.history.registerUndo(withTarget: editor) { target in
            undone += 1
            target.history.registerUndo(withTarget: target) { _ in undone += 1 }
        }

        #expect(try coordinator.handle(command("z", keyCode: 6)) == nil)

        #expect(undone == 1)
        #expect(!shelfUndone)
        #expect(editor.history.canRedo)
        #expect(try coordinator.handle(command("z", keyCode: 6, shift: true)) == nil)
        #expect(!editor.history.canRedo)
    }

    @Test("⌘Z in an empty search field undoes the shelf's last action, not the field")
    func whenFieldIsEmpty_thenUndoGoesToTheShelf() throws {
        let (coordinator, editor) = makeFixture(text: "")
        var shelfUndone = false
        coordinator.onUndo = { shelfUndone = true }
        coordinator.searchTextIsEmpty = { true }
        editor.history.registerUndo(withTarget: editor) { _ in }

        #expect(try coordinator.handle(command("z", keyCode: 6)) == nil)

        #expect(shelfUndone)
        #expect(!editor.history.canRedo)
    }

    @Test(
        "Ctrl, Option and ⌥⌘ combinations of A, C, V, X and Z are not taken as Edit shortcuts",
        arguments: [UInt16(0), 6, 7, 8, 9],
        [NSEvent.ModifierFlags.option, .control, [.command, .option]]
    )
    func whenModifiersDiffer_thenTheFieldEditorIsNotDriven(keyCode: UInt16, flags: NSEvent.ModifierFlags) throws {
        let (coordinator, editor) = makeFixture()
        var clipsSelected = false
        coordinator.onSelectAll = { clipsSelected = true }
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: keyCode
        ))

        _ = coordinator.handle(event)

        #expect(editor.calls.isEmpty)
        #expect(!clipsSelected)
        #expect(editor.selectedRange.length == 0)
    }

    @Test("in the grid, with no text field focused, ⌘A selects the clips shown and ⌘X, ⌘C and ⌘V never touch a field")
    func whenGridHasFocus_thenCommandASelectsClips() throws {
        let editor = SpyFieldEditor(frame: .zero)
        let coordinator = KeyNavCoordinator()
        coordinator.isOverlayVisible = true
        coordinator.hostWindow = window
        var clipsSelected = false
        coordinator.onSelectAll = { clipsSelected = true }

        #expect(try coordinator.handle(command("a", keyCode: 0)) == nil)
        for (key, code) in [("x", UInt16(7)), ("v", 9)] {
            _ = try coordinator.handle(command(key, keyCode: code))
        }

        #expect(clipsSelected)
        #expect(editor.calls.isEmpty)
    }

    @Test("a real AppKit field editor mutates its text on ⌘A, ⌘X, ⌘V, ⌘Z and ⇧⌘Z, then selects clips on a second ⌘A")
    func whenRealFieldEditorIsDriven_thenEditShortcutsMutateTextAndSecondCommandASelectsClips() throws {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        field.stringValue = "invoice"
        window.contentView?.addSubview(field)
        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.allowsUndo = true
        editor.setSelectedRange(NSRange(location: 7, length: 0))

        let coordinator = KeyNavCoordinator()
        coordinator.isOverlayVisible = true
        coordinator.hostWindow = window
        coordinator.isSearchActive = true
        coordinator.searchTextIsEmpty = { editor.string.isEmpty }
        var clipsSelected = false
        coordinator.onSelectAll = { clipsSelected = true }

        #expect(try coordinator.handle(command("a", keyCode: 0)) == nil)
        #expect(editor.selectedRange() == NSRange(location: 0, length: 7))
        #expect(!clipsSelected)

        #expect(try coordinator.handle(command("a", keyCode: 0)) == nil)
        #expect(clipsSelected, "second ⌘A with all text selected must select the shelf's clips")

        editor.insertText("receipt", replacementRange: NSRange(location: 0, length: 7))
        #expect(editor.string == "receipt")

        #expect(try coordinator.handle(command("z", keyCode: 6)) == nil)
        #expect(editor.string == "invoice", "⌘Z undoes the edit in the real field editor")

        #expect(try coordinator.handle(command("z", keyCode: 6, shift: true)) == nil)
        #expect(editor.string == "receipt", "⇧⌘Z redoes the edit in the real field editor")
    }
}
