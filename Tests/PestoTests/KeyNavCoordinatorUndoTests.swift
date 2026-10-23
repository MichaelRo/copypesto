// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import Testing
@testable import Pesto

@Suite("KeyNavCoordinator — undo and redo")
@MainActor
struct KeyNavCoordinatorUndoTests {
    private let window = KeyNavCoordinatorUndoTests.makeWindow()

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

    @Test("⌘Z undoes and ⇧⌘Z redoes in the grid, and each is consumed")
    func whenZInTheGrid_thenUndoAndRedoFire() throws {
        let coordinator = makeCoordinator()
        var undone = 0
        var redone = 0
        coordinator.onUndo = { undone += 1 }
        coordinator.onRedo = { redone += 1 }

        #expect(try coordinator.handle(keyEvent(keyCode: 6, modifiers: .command)) == nil)
        #expect((undone, redone) == (1, 0))
        #expect(try coordinator.handle(keyEvent(keyCode: 6, modifiers: [.command, .shift])) == nil)
        #expect((undone, redone) == (1, 1))
    }

    @Test("⌘Z while searching is left to the search field, which undoes its own typing")
    func whenZInSearch_thenTheFieldKeepsIt() throws {
        let coordinator = makeCoordinator()
        coordinator.isSearchActive = true
        var fired = false
        coordinator.onUndo = { fired = true }
        coordinator.onRedo = { fired = true }

        let undo = try keyEvent(keyCode: 6, modifiers: .command)
        let redo = try keyEvent(keyCode: 6, modifiers: [.command, .shift])

        #expect(coordinator.handle(undo) === undo)
        #expect(coordinator.handle(redo) === redo)
        #expect(!fired)
    }

    @Test("⌘Z in a search field with no text reaches the shelf, because there is no typing to undo")
    func whenZInAnEmptySearch_thenTheShelfUndoes() throws {
        let coordinator = makeCoordinator()
        coordinator.isSearchActive = true
        var undone = 0
        var redone = 0
        var searchText = ""
        coordinator.onUndo = { undone += 1 }
        coordinator.onRedo = { redone += 1 }
        coordinator.searchTextIsEmpty = { searchText.isEmpty }

        #expect(try coordinator.handle(keyEvent(keyCode: 6, modifiers: .command)) == nil)
        #expect(try coordinator.handle(keyEvent(keyCode: 6, modifiers: [.command, .shift])) == nil)
        #expect((undone, redone) == (1, 1))

        searchText = "abc"
        let typed = try keyEvent(keyCode: 6, modifiers: .command)
        #expect(coordinator.handle(typed) === typed)
        #expect(undone == 1)
    }

    @Test("⌘Z on the lock screen undoes nothing")
    func whenZWhileLocked_thenNothingFires() throws {
        let coordinator = makeCoordinator()
        coordinator.isLocked = true
        var fired = false
        coordinator.onUndo = { fired = true }
        coordinator.onRedo = { fired = true }

        _ = try coordinator.handle(keyEvent(keyCode: 6, modifiers: .command))
        _ = try coordinator.handle(keyEvent(keyCode: 6, modifiers: [.command, .shift]))

        #expect(!fired)
    }
}
