// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import Testing
@testable import Pesto

/// Regression coverage for the NSBeep bug: `start()`'s monitor closure used
/// `self?.handle(event) ?? event`, which flattens `NSEvent??` to `NSEvent?` — a legitimate
/// `nil` from `handle()` (meaning "consumed") was indistinguishable from a deallocated `self`,
/// so `?? event` handed the original event back to AppKit and it fell through to
/// `OverlayPanel.keyDown` → `super.keyDown` → NSBeep on every arrow/Return/Space/Delete/Tab
/// press. These tests drive `handle(_:)` directly (no real event loop needed) and assert both
/// that the callback fires AND that the event is consumed (`nil`).
@Suite("KeyNavCoordinator — event consumption")
@MainActor
struct KeyNavCoordinatorTests {
    private let window = KeyNavCoordinatorTests.makeWindow()

    private static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }

    private func keyEvent(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        in target: NSWindow? = nil
    ) throws
    -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: (target ?? window).windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    private func makeCoordinator() -> KeyNavCoordinator {
        let coordinator = KeyNavCoordinator()
        coordinator.isOverlayVisible = true
        coordinator.hostWindow = window
        return coordinator
    }

    @Test("right arrow fires onRight and consumes the event")
    func rightArrow_firesCallback_andConsumesEvent() throws {
        let coordinator = makeCoordinator()
        var fired = false
        coordinator.onRight = { fired = true }

        let result = try coordinator.handle(keyEvent(keyCode: 124))

        #expect(fired)
        #expect(result == nil)
    }

    @Test("left arrow fires onLeft and consumes the event")
    func leftArrow_firesCallback_andConsumesEvent() throws {
        let coordinator = makeCoordinator()
        var fired = false
        coordinator.onLeft = { fired = true }

        let result = try coordinator.handle(keyEvent(keyCode: 123))

        #expect(fired)
        #expect(result == nil)
    }

    @Test("Control-Option-Arrow (VoiceOver navigation) passes through without moving the grid focus")
    func whenControlOptionArrow_thenPassesThroughWithoutMovingGridFocus() throws {
        let coordinator = makeCoordinator()
        var fired = false
        coordinator.onRight = { fired = true }
        coordinator.onLeft = { fired = true }
        coordinator.onPage = { _ in fired = true }

        let right = try keyEvent(keyCode: 124, modifiers: [.control, .option])
        let left = try keyEvent(keyCode: 123, modifiers: [.control, .option])
        let down = try keyEvent(keyCode: 125, modifiers: [.control, .option])
        let up = try keyEvent(keyCode: 126, modifiers: [.control, .option])

        #expect(coordinator.handle(right) === right)
        #expect(coordinator.handle(left) === left)
        #expect(coordinator.handle(down) === down)
        #expect(coordinator.handle(up) === up)

        coordinator.isSearchActive = true
        #expect(coordinator.handle(down) === down)
        #expect(coordinator.handle(up) === up)
        coordinator.isSearchActive = false

        coordinator.isLocked = true
        #expect(coordinator.handle(right) === right)
        coordinator.isLocked = false

        coordinator.isConfirming = true
        #expect(coordinator.handle(right) === right)
        #expect(!fired)
    }

    @Test("up/down arrows are silently consumed (no vertical grid)")
    func verticalArrows_areConsumedWithoutCallback() throws {
        let coordinator = makeCoordinator()
        #expect(try coordinator.handle(keyEvent(keyCode: 125)) == nil) // down
        #expect(try coordinator.handle(keyEvent(keyCode: 126)) == nil) // up
    }

    @Test("Return fires onReturn and consumes the event")
    func returnKey_firesCallback_andConsumesEvent() throws {
        let coordinator = makeCoordinator()
        var fired = false
        coordinator.onReturn = { fired = true }

        let result = try coordinator.handle(keyEvent(keyCode: 36))

        #expect(fired)
        #expect(result == nil)
    }

    @Test("Space fires onSpace and consumes the event")
    func spaceKey_firesCallback_andConsumesEvent() throws {
        let coordinator = makeCoordinator()
        var fired = false
        coordinator.onSpace = { fired = true }

        let result = try coordinator.handle(keyEvent(keyCode: 49))

        #expect(fired)
        #expect(result == nil)
    }

    @Test("Delete fires onDelete and consumes the event")
    func deleteKey_firesCallback_andConsumesEvent() throws {
        let coordinator = makeCoordinator()
        var fired = false
        coordinator.onDelete = { fired = true }

        let result = try coordinator.handle(keyEvent(keyCode: 51))

        #expect(fired)
        #expect(result == nil)
    }

    @Test("Tab and Shift+Tab pass through to the responder chain")
    func tab_passesThroughToTheResponderChain() throws {
        let coordinator = makeCoordinator()
        #expect(try coordinator.handle(keyEvent(keyCode: 48)) != nil)
        #expect(try coordinator.handle(keyEvent(keyCode: 48, modifiers: .shift)) != nil)
    }

    @Test("a Cmd-modified key nothing owns is swallowed, except the app and window commands (A-05)")
    func unhandledCommandKey_isSwallowedButNotTheAppCommands() throws {
        let coordinator = makeCoordinator()
        // Cmd+J is bound to nothing: left alone, AppKit beeps for it. Quit, Hide, Close and Minimize are the app's
        // own, so they must reach it (`KeyNavUnownedKeysTests`).
        #expect(try coordinator.handle(keyEvent(keyCode: 38, modifiers: .command)) == nil)
        #expect(try coordinator.handle(keyEvent(keyCode: 12, modifiers: .command)) != nil)
    }

    @Test("Cmd+, opens Settings, Cmd+N starts a new collection, Cmd+P pastes all, Shift+Cmd+P pastes one by one")
    func toolbarShortcuts_fireAndConsume() throws {
        let coordinator = makeCoordinator()
        var openedSettings = false
        var startedNewCollection = false
        var pastedAll = false
        var pastedOneByOne = false
        coordinator.onOpenSettings = { openedSettings = true }
        coordinator.onNewCollection = { startedNewCollection = true }
        coordinator.onPasteAllSelected = { pastedAll = true }
        coordinator.onPasteSelectedOneByOne = { pastedOneByOne = true }

        #expect(try coordinator.handle(keyEvent(keyCode: 43, modifiers: .command)) == nil) // ⌘,
        #expect(try coordinator.handle(keyEvent(keyCode: 45, modifiers: .command)) == nil) // ⌘N
        #expect(try coordinator.handle(keyEvent(keyCode: 35, modifiers: .command)) == nil) // ⌘P
        #expect(pastedAll && !pastedOneByOne)
        #expect(try coordinator.handle(keyEvent(keyCode: 35, modifiers: [.command, .shift])) == nil) // ⇧⌘P

        #expect(openedSettings)
        #expect(startedNewCollection)
        #expect(pastedOneByOne)
    }

    @Test("⌘K opens the focused card's actions, also while searching, and not while the history is locked")
    func commandK_showsTheFocusedCardsActions() throws {
        let coordinator = makeCoordinator()
        var shown = 0
        coordinator.onShowActions = { shown += 1 }

        #expect(try coordinator.handle(keyEvent(keyCode: 40, modifiers: .command)) == nil)
        coordinator.isSearchActive = true
        #expect(try coordinator.handle(keyEvent(keyCode: 40, modifiers: .command)) == nil)
        coordinator.isSearchActive = false
        coordinator.isLocked = true
        _ = try coordinator.handle(keyEvent(keyCode: 40, modifiers: .command))

        #expect(shown == 2)
    }

    @Test("⌘1 to ⌘9 paste the card in that position, and ⌘0 does nothing, quietly")
    func cardNumberShortcuts_pasteThatPosition() throws {
        let coordinator = makeCoordinator()
        var pasted: [Int] = []
        coordinator.onPasteNth = { pasted.append($0) }
        let keyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

        for code in keyCodes {
            #expect(try coordinator.handle(keyEvent(keyCode: code, modifiers: .command)) == nil)
        }
        let zero = try coordinator.handle(keyEvent(keyCode: 29, modifiers: .command)) // ⌘0

        #expect(pasted == Array(1...9))
        #expect(zero == nil, "⌘0 is not a card shortcut, and is swallowed rather than beeping")
    }

    @Test("a bare number key is typed into search, not treated as a card shortcut")
    func bareNumber_isNotACardShortcut() throws {
        let coordinator = makeCoordinator()
        var pasted = false
        coordinator.onPasteNth = { _ in pasted = true }

        _ = try coordinator.handle(keyEvent(keyCode: 18, modifiers: []))

        #expect(!pasted)
    }

    @Test("toolbar shortcuts also fire while search is active")
    func toolbarShortcuts_fireDuringSearch() throws {
        let coordinator = makeCoordinator()
        coordinator.isSearchActive = true
        var openedSettings = false
        coordinator.onOpenSettings = { openedSettings = true }

        #expect(try coordinator.handle(keyEvent(keyCode: 43, modifiers: .command)) == nil)

        #expect(openedSettings)
    }

    // MARK: - History lock

    @Test("while the history is locked, Return, Space, Delete and letters do nothing and are consumed")
    func whenLocked_thenGridKeysAreInert() throws {
        let coordinator = makeCoordinator()
        coordinator.isLocked = true
        var fired: [String] = []
        coordinator.onReturn = { fired.append("return") }
        coordinator.onSpace = { fired.append("space") }
        coordinator.onDelete = { fired.append("delete") }
        coordinator.onSelectAll = { fired.append("selectAll") }
        coordinator.onCharacterTyped = { _ in fired.append("char") }

        for code: UInt16 in [36, 49, 51, 117, 123, 124, 125, 126] {
            #expect(try coordinator.handle(keyEvent(keyCode: code)) == nil)
        }
        #expect(try coordinator.handle(keyEvent(keyCode: 0, modifiers: .command)) == nil)

        #expect(fired.isEmpty, "locked keys reached the grid: \(fired)")
    }

    @Test("while locked, Escape still closes the shelf")
    func whenLocked_thenEscapeStillCloses() throws {
        let coordinator = makeCoordinator()
        coordinator.isLocked = true
        var closed = false
        coordinator.onEscape = { closed = true }

        _ = try coordinator.handle(keyEvent(keyCode: 53))

        #expect(closed)
    }

    // MARK: - Keyboard-only users

    @Test("while locked, Return unlocks, and Tab reaches the buttons on the lock screen")
    func whenLocked_thenReturnUnlocksAndTabPassesThrough() throws {
        let coordinator = makeCoordinator()
        coordinator.isLocked = true
        var unlocked = 0
        coordinator.onUnlock = { unlocked += 1 }

        #expect(try coordinator.handle(keyEvent(keyCode: 36)) == nil)
        let tab = try keyEvent(keyCode: 48)
        #expect(try coordinator.handle(tab) === tab, "Tab must reach the Try Again and Use Password buttons")

        #expect(unlocked == 1)
    }

    private func windowFocusing(_ responder: NSView) -> NSWindow {
        let target = Self.makeWindow()
        let content = NSView(frame: target.contentLayoutRect)
        content.addSubview(responder)
        target.contentView = content
        #expect(target.makeFirstResponder(responder))
        return target
    }

    @Test("while locked, Return and Space press a focused button instead of being swallowed")
    func whenLockedAndAButtonHasFocus_thenItIsPressed() throws {
        let button = NSButton(title: "Use Password", target: nil, action: nil)
        let target = windowFocusing(button)
        let coordinator = KeyNavCoordinator()
        coordinator.isOverlayVisible = true
        coordinator.hostWindow = target
        coordinator.isLocked = true
        var unlocked = false
        coordinator.onUnlock = { unlocked = true }

        let returnKey = try keyEvent(keyCode: 36, in: target)
        let space = try keyEvent(keyCode: 49, in: target)

        #expect(try coordinator.handle(returnKey) === returnKey)
        #expect(try coordinator.handle(space) === space)
        #expect(!unlocked, "the focused button does the unlocking, not the shortcut")
    }

    @Test("unlocked, Return and Space with a button focused press it and do not paste or select a card")
    func whenAButtonHasFocus_thenGridKeysLeaveItAlone() throws {
        let button = NSButton(title: "Merge", target: nil, action: nil)
        let target = windowFocusing(button)
        let coordinator = KeyNavCoordinator()
        coordinator.isOverlayVisible = true
        coordinator.hostWindow = target
        var fired: [String] = []
        coordinator.onReturn = { fired.append("return") }
        coordinator.onSpace = { fired.append("space") }

        let returnKey = try keyEvent(keyCode: 36, in: target)
        let space = try keyEvent(keyCode: 49, in: target)

        #expect(try coordinator.handle(returnKey) === returnKey)
        #expect(try coordinator.handle(space) === space)
        #expect(fired.isEmpty)
    }

    @Test("with no control focused, Return and Space still drive the grid")
    func whenNoControlHasFocus_thenGridKeysStillWork() throws {
        let coordinator = makeCoordinator()
        var fired: [String] = []
        coordinator.onReturn = { fired.append("return") }
        coordinator.onSpace = { fired.append("space") }

        #expect(try coordinator.handle(keyEvent(keyCode: 36)) == nil)
        #expect(try coordinator.handle(keyEvent(keyCode: 49)) == nil)

        #expect(fired == ["return", "space"])
    }

    // MARK: - Search results by keyboard

    @Test("in search mode, Return pastes the focused result and still reaches the field, so history is saved")
    func whenSearching_thenReturnPastesTheFocusedResult() throws {
        let coordinator = makeCoordinator()
        coordinator.isSearchActive = true
        var pasted = false
        coordinator.onReturnFromSearch = { pasted = true }
        let event = try keyEvent(keyCode: 36)

        let result = coordinator.handle(event)

        #expect(pasted)
        #expect(result === event)
    }

    @Test("while the shelf asks before a delete, Return confirms and Escape cancels, and neither reaches the grid")
    func whenConfirming_thenReturnConfirmsAndEscapeCancels() throws {
        let coordinator = makeCoordinator()
        coordinator.isConfirming = true
        var confirmed = false
        var cancelled = false
        var pasted = false
        var closed = false
        coordinator.onConfirm = { confirmed = true }
        coordinator.onCancelConfirmation = { cancelled = true }
        coordinator.onReturn = { pasted = true }
        coordinator.onEscape = { closed = true }

        #expect(try coordinator.handle(keyEvent(keyCode: 36)) == nil)
        #expect(try coordinator.handle(keyEvent(keyCode: 53)) == nil)

        #expect(confirmed)
        #expect(cancelled)
        #expect(!pasted, "Return on the question must not paste the focused clip")
        #expect(!closed, "Escape on the question must not close the shelf")
    }

    @Test("while the shelf asks before a delete, every other key is swallowed: it neither types nor navigates")
    func whenConfirming_thenOtherKeysDoNothing() throws {
        let coordinator = makeCoordinator()
        coordinator.isConfirming = true
        var typed = false
        var moved = false
        var deleted = false
        coordinator.onCharacterTyped = { _ in typed = true }
        coordinator.onRight = { moved = true }
        coordinator.onDelete = { deleted = true }

        #expect(try coordinator.handle(keyEvent(keyCode: 0)) == nil)
        #expect(try coordinator.handle(keyEvent(keyCode: 124)) == nil)
        #expect(try coordinator.handle(keyEvent(keyCode: 51)) == nil)
        #expect(try coordinator.handle(keyEvent(keyCode: 40, modifiers: .command)) == nil)

        #expect(!typed && !moved && !deleted)
    }

    @Test("Tab still reaches the question's buttons")
    func whenConfirming_thenTabPassesThrough() throws {
        let coordinator = makeCoordinator()
        coordinator.isConfirming = true
        let event = try keyEvent(keyCode: 48)

        #expect(coordinator.handle(event) === event)
    }

    @Test("in search mode, ⌘Return asks Pesto and is consumed, so it neither pastes nor reaches the field")
    func whenSearching_thenCommandReturnAsks() throws {
        let coordinator = makeCoordinator()
        coordinator.isSearchActive = true
        var asked = false
        var pasted = false
        coordinator.onAskFromSearch = { asked = true }
        coordinator.onReturnFromSearch = { pasted = true }

        let result = try coordinator.handle(keyEvent(keyCode: 36, modifiers: .command))

        #expect(asked)
        #expect(!pasted)
        #expect(result == nil)
    }

    @Test("outside search, ⌘Return shows or hides the focused covered clip and is consumed")
    func whenNotSearching_thenCommandReturnShowsTheFocusedClip() throws {
        let coordinator = makeCoordinator()
        var shown = false
        var asked = false
        var pasted = false
        coordinator.onShowHidden = { shown = true }
        coordinator.onAskFromSearch = { asked = true }
        coordinator.onReturn = { pasted = true }

        let result = try coordinator.handle(keyEvent(keyCode: 36, modifiers: .command))

        #expect(shown)
        #expect(!asked)
        #expect(!pasted, "⌘Return must not paste")
        #expect(result == nil)
    }

    @Test("in search mode, Down and Up move the focused result and are consumed")
    func whenSearching_thenUpAndDownMoveFocus() throws {
        let coordinator = makeCoordinator()
        coordinator.isSearchActive = true
        var moves: [String] = []
        coordinator.onRight = { moves.append("next") }
        coordinator.onLeft = { moves.append("previous") }

        #expect(try coordinator.handle(keyEvent(keyCode: 125)) == nil)
        #expect(try coordinator.handle(keyEvent(keyCode: 126)) == nil)

        #expect(moves == ["next", "previous"])
    }

    @Test("when the overlay is not visible, the event passes through unconsumed")
    func overlayNotVisible_passesEventThrough() throws {
        let coordinator = KeyNavCoordinator()
        coordinator.isOverlayVisible = false
        let event = try keyEvent(keyCode: 124)

        #expect(coordinator.handle(event) === event)
    }

    // MARK: - Only the host window's keys (the monitor is app-wide)
}

extension KeyNavCoordinatorTests {
    @Test("a key typed in another window passes through untouched")
    func keyInAnotherWindow_isNotConsumed() throws {
        let coordinator = makeCoordinator()
        var fired = false
        coordinator.onDelete = { fired = true }
        let other = KeyNavCoordinatorTests.makeWindow()
        let event = try keyEvent(keyCode: 51, in: other)

        let result = coordinator.handle(event)

        #expect(result === event, "Backspace typed in Settings must reach its text field")
        #expect(!fired)
    }

    @Test("before the host window is known, nothing is consumed")
    func withoutAHostWindow_nothingIsConsumed() throws {
        let coordinator = KeyNavCoordinator()
        coordinator.isOverlayVisible = true
        let event = try keyEvent(keyCode: 124)

        #expect(coordinator.handle(event) === event)
    }

    // MARK: - A text field being edited keeps its keys

    @Test(
        "while a card's title is being edited, typing, deleting, Escape and the arrows all reach the field",
        arguments: [UInt16(0), 51, 53, 123, 124, 117]
    )
    func whileATextFieldIsFocused_thenTheGridLeavesTheKeyAlone(keyCode: UInt16) throws {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        window.contentView?.addSubview(textView)
        #expect(window.makeFirstResponder(textView))
        let coordinator = makeCoordinator()
        var fired = false
        coordinator.onCharacterTyped = { _ in fired = true }
        coordinator.onDelete = { fired = true }
        coordinator.onEscape = { fired = true }
        coordinator.onLeft = { fired = true }
        coordinator.onRight = { fired = true }
        let event = try keyEvent(keyCode: keyCode)

        let result = coordinator.handle(event)

        #expect(result === event, "key \(keyCode) was taken from the text field")
        #expect(!fired)
    }

    @Test("Cmd+F fires onSearch and consumes the event")
    func commandF_firesOnSearch_andConsumesEvent() throws {
        let coordinator = makeCoordinator()
        var fired = false
        coordinator.onSearch = { fired = true }

        let event = try keyEvent(keyCode: 3, modifiers: [.command])
        let result = coordinator.handle(event)

        #expect(result == nil, "Cmd+F must be consumed")
        #expect(fired, "onSearch must fire")
    }
}

extension KeyNavCoordinatorTests {
    @Test("in search mode, Right and Left move the focused result and are consumed")
    func whenSearching_thenRightAndLeftMoveFocus() throws {
        let coordinator = makeCoordinator()
        coordinator.isSearchActive = true
        var moves: [String] = []
        coordinator.onRight = { moves.append("next") }
        coordinator.onLeft = { moves.append("previous") }

        #expect(try coordinator.handle(keyEvent(keyCode: 124)) == nil)
        #expect(try coordinator.handle(keyEvent(keyCode: 123)) == nil)

        #expect(moves == ["next", "previous"])
    }

    @Test(
        "in search mode, an arrow with ⌘, ⌥, ⇧ or ⌃ and Home and End still reach the text field",
        arguments: [
            "123:command", "123:option", "123:shift", "123:control",
            "124:command", "124:option", "124:shift", "124:control", "115:", "119:"
        ]
    )
    func whenSearching_thenCaretEditingKeysAreNotMovedToCards(key: String) throws {
        let parts = key.split(separator: ":", omittingEmptySubsequences: false)
        let keyCode = try #require(UInt16(parts[0]))
        let modifiers: NSEvent.ModifierFlags = switch parts[1] {
        case "command": .command
        case "option": .option
        case "shift": .shift
        case "control": .control
        default: []
        }
        let coordinator = makeCoordinator()
        coordinator.isSearchActive = true
        var moved = false
        coordinator.onLeft = { moved = true }
        coordinator.onRight = { moved = true }
        coordinator.onFirst = { moved = true }
        coordinator.onLast = { moved = true }
        coordinator.onPage = { _ in moved = true }
        let event = try keyEvent(keyCode: keyCode, modifiers: modifiers)

        #expect(coordinator.handle(event) === event)
        #expect(!moved)
    }
}
