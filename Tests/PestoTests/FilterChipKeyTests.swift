// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import Testing
@testable import Pesto

@Suite("Shelf keys: the search filter chips")
@MainActor
struct FilterChipKeyTests {
    private func coordinator() throws -> (KeyNavCoordinator, NSWindow) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let coordinator = KeyNavCoordinator()
        coordinator.isOverlayVisible = true
        coordinator.isSearchActive = true
        coordinator.hostWindow = window
        return (coordinator, window)
    }

    private func key(_ code: UInt16, in window: NSWindow, shift: Bool = false) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: shift ? .shift : [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: code
        ))
    }

    @Test("Tab moves forward through the chips and Shift-Tab back, and both are consumed")
    func tab_movesTheCursor() throws {
        let (coordinator, window) = try coordinator()
        var moves: [Int] = []
        coordinator.onFilterChipMove = { moves.append($0)
            return true
        }

        #expect(try coordinator.handle(key(48, in: window)) == nil)
        #expect(try coordinator.handle(key(48, in: window, shift: true)) == nil)

        #expect(moves == [1, -1])
    }

    @Test("with no chips Tab goes on to the system")
    func tab_withoutChipsIsNotConsumed() throws {
        let (coordinator, window) = try coordinator()
        coordinator.onFilterChipMove = { _ in false }

        #expect(try coordinator.handle(key(48, in: window)) != nil)
    }

    @Test("Return and Space toggle the chip under the cursor instead of pasting or typing a space")
    func returnAndSpace_toggleTheChip() throws {
        let (coordinator, window) = try coordinator()
        var toggles = 0
        var pasted = false
        coordinator.onFilterChipToggle = { toggles += 1
            return true
        }
        coordinator.onReturnFromSearch = { pasted = true }

        #expect(try coordinator.handle(key(36, in: window)) == nil)
        #expect(try coordinator.handle(key(49, in: window)) == nil)

        #expect(toggles == 2)
        #expect(!pasted, "Return on a chip must not paste")
    }

    @Test("with the cursor on the field, Return pastes as before and Space is typed")
    func returnAndSpace_onTheFieldAreUnchanged() throws {
        let (coordinator, window) = try coordinator()
        coordinator.onFilterChipToggle = { false }
        var pasted = false
        coordinator.onReturnFromSearch = { pasted = true }

        _ = try coordinator.handle(key(36, in: window))
        #expect(try coordinator.handle(key(49, in: window)) != nil, "Space belongs to the search field")

        #expect(pasted)
    }

    @Test("Esc on a chip goes back to the field and keeps the search open; Esc on the field closes it")
    func escape_leavesTheChipFirst() throws {
        let (coordinator, window) = try coordinator()
        var onChip = true
        var closed = false
        coordinator.onFilterChipRelease = { defer { onChip = false }
            return onChip
        }
        coordinator.onEscapeFromSearch = { closed = true }

        #expect(try coordinator.handle(key(53, in: window)) == nil)
        #expect(!closed)
        #expect(try coordinator.handle(key(53, in: window)) == nil)
        #expect(closed)
    }
}
