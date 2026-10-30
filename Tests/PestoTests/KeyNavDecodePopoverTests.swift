// SPDX-License-Identifier: MIT
import AppKit
import Testing
@testable import Pesto

@Suite("KeyNavCoordinator: the Decode JWT popover owns Escape and Return")
@MainActor
struct KeyNavDecodePopoverTests {
    private let window: NSWindow = {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }()

    private func keyEvent(_ keyCode: UInt16) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode
        ))
    }

    @Test("Escape closes the open popover and Return copies, and neither reaches the grid")
    func whenPopoverOpen_thenEscapeClosesAndReturnCopies() throws {
        let coordinator = KeyNavCoordinator()
        coordinator.hostWindow = window
        coordinator.isOverlayVisible = true
        var closed = 0
        var copied = 0
        var gridKey = false
        coordinator.onReturn = { gridKey = true }
        coordinator.onEscape = { gridKey = true }
        let keys = DecodePopoverKeys(close: { closed += 1 }, copy: { copied += 1 })
        coordinator.decodePopoverKeys = { keys }

        #expect(try coordinator.handle(keyEvent(53)) == nil)
        #expect(try coordinator.handle(keyEvent(36)) == nil)

        #expect(closed == 1 && copied == 1)
        #expect(!gridKey)
    }

    @Test("with no popover open, Escape reaches the grid")
    func whenNoPopover_thenEscapeReachesGrid() throws {
        let coordinator = KeyNavCoordinator()
        coordinator.hostWindow = window
        coordinator.isOverlayVisible = true
        var escaped = false
        coordinator.onEscape = { escaped = true }
        coordinator.decodePopoverKeys = { nil }

        _ = try coordinator.handle(keyEvent(53))

        #expect(escaped)
    }
}
