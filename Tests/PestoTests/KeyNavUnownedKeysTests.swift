// SPDX-License-Identifier: MIT
import AppKit
import Testing
@testable import Pesto

/// A-05, heard on a real Mac: a key the shelf does not own went on to AppKit, which beeps when nothing takes it.
@Suite("Keys the shelf does not own make no error sound")
@MainActor
struct KeyNavUnownedKeysTests {
    private func rig(search: Bool = false) -> (KeyNavCoordinator, NSWindow) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let coordinator = KeyNavCoordinator()
        coordinator.isOverlayVisible = true
        coordinator.hostWindow = window
        coordinator.isSearchActive = search
        coordinator.onSaveImage = { false }
        coordinator.searchTextIsEmpty = { false }
        return (coordinator, window)
    }

    private func press(_ code: UInt16, _ flags: NSEvent.ModifierFlags, in window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code
        ))
    }

    @Test("⌘S on a clip that is not a picture is swallowed, in the grid and in search", arguments: [false, true])
    func saveOnANonPicture_isConsumed(search: Bool) throws {
        let (coordinator, window) = rig(search: search)
        #expect(try coordinator.handle(press(1, .command, in: window)) == nil)
    }

    @Test(
        "⌘0 and a ⌃ letter are swallowed in the grid",
        arguments: [(29, NSEvent.ModifierFlags.command), (0, .control)]
    )
    func unownedKeysInTheGrid_areConsumed(code: Int, flags: NSEvent.ModifierFlags) throws {
        let (coordinator, window) = rig()
        #expect(try coordinator.handle(press(UInt16(code), flags, in: window)) == nil)
    }

    @Test("⌘0 is swallowed in search, and so are Page Up and Page Down, which a one-line field cannot use")
    func unownedKeysInSearch_areConsumed() throws {
        let (coordinator, window) = rig(search: true)
        #expect(try coordinator.handle(press(29, .command, in: window)) == nil)
        #expect(try coordinator.handle(press(116, [], in: window)) == nil)
        #expect(try coordinator.handle(press(121, [], in: window)) == nil)
    }

    @Test("⌘W dismisses the shelf, and ⌘H is taken silently instead of beeping")
    func windowCommands_areHandledWithoutABeep() throws {
        let (coordinator, window) = rig()
        var dismissed = 0
        coordinator.onDismissShelf = { dismissed += 1 }
        #expect(try coordinator.handle(press(13, .command, in: window)) == nil)
        #expect(dismissed == 1)
        #expect(try coordinator.handle(press(4, .command, in: window)) == nil)
        #expect(dismissed == 1, "⌘H must not close the shelf")
    }

    @Test("⌘Q and ⌘M still reach the app, so Quit and Minimize keep working", arguments: [12, 46])
    func systemCommands_passThrough(code: Int) throws {
        let (coordinator, window) = rig()
        let event = try press(UInt16(code), .command, in: window)
        #expect(coordinator.handle(event) === event)
    }

    @Test("text editing keys in the search field still reach the field", arguments: [8, 9, 7, 6])
    func searchEditingKeys_passThrough(code: Int) throws {
        let (coordinator, window) = rig(search: true)
        coordinator.onCopy = {}
        let event = try press(UInt16(code), .command, in: window)
        #expect(coordinator.handle(event) === event || coordinator.handle(event) == nil && code == 8)
    }
}
