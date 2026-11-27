// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import Testing
@testable import Pesto

@Suite("KeyNavCoordinator — search caret and card navigation")
@MainActor
struct KeyNavSearchArrowTests {
    private func keyEvent(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        in window: NSWindow
    ) throws
    -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    private func makeCoordinator() -> (KeyNavCoordinator, NSWindow) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let coordinator = KeyNavCoordinator()
        coordinator.isOverlayVisible = true
        coordinator.isSearchActive = true
        coordinator.hostWindow = window
        return (coordinator, window)
    }

    @Test("with typed search text, bare Left and Right pass through to move the caret")
    func whenSearchHasText_thenLeftRightPassThroughToField() throws {
        let (coordinator, window) = makeCoordinator()
        coordinator.searchTextIsEmpty = { false }
        var moves: [String] = []
        coordinator.onLeft = { moves.append("left") }
        coordinator.onRight = { moves.append("right") }

        let left = try keyEvent(keyCode: 123, in: window)
        let right = try keyEvent(keyCode: 124, in: window)

        #expect(coordinator.handle(left) === left)
        #expect(coordinator.handle(right) === right)
        #expect(moves.isEmpty)
    }

    @Test("with typed search text, Up/Down move cards and Return pastes the selected clip")
    func whenSearchHasText_thenUpDownMoveCardsAndReturnPastes() throws {
        let (coordinator, window) = makeCoordinator()
        coordinator.searchTextIsEmpty = { false }
        var moves: [String] = []
        var pasted = false
        var pastedPlain = false
        coordinator.onLeft = { moves.append("previous") }
        coordinator.onRight = { moves.append("next") }
        coordinator.onReturnFromSearch = { pasted = true }
        coordinator.onReturnPlainFromSearch = { pastedPlain = true }

        #expect(try coordinator.handle(keyEvent(keyCode: 125, in: window)) == nil)
        #expect(try coordinator.handle(keyEvent(keyCode: 126, in: window)) == nil)
        #expect(moves == ["next", "previous"])

        let ret = try keyEvent(keyCode: 36, in: window)
        #expect(coordinator.handle(ret) === ret)
        #expect(pasted)

        let shiftRet = try keyEvent(keyCode: 36, modifiers: .shift, in: window)
        #expect(coordinator.handle(shiftRet) === shiftRet)
        #expect(pastedPlain)
    }

    @Test("when search text becomes empty again, bare Left and Right resume moving cards")
    func whenSearchCleared_thenLeftRightMoveCardsAgain() throws {
        let (coordinator, window) = makeCoordinator()
        var query = "typo"
        coordinator.searchTextIsEmpty = { query.isEmpty }
        var moves: [String] = []
        coordinator.onLeft = { moves.append("previous") }
        coordinator.onRight = { moves.append("next") }

        let leftWhileTyping = try keyEvent(keyCode: 123, in: window)
        #expect(coordinator.handle(leftWhileTyping) === leftWhileTyping)
        #expect(moves.isEmpty)

        query = ""
        #expect(try coordinator.handle(keyEvent(keyCode: 124, in: window)) == nil)
        #expect(try coordinator.handle(keyEvent(keyCode: 123, in: window)) == nil)
        #expect(moves == ["next", "previous"])
    }
}
