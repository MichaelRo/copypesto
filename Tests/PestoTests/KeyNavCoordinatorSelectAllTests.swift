// SPDX-License-Identifier: MIT
import AppKit
import Testing
@testable import Pesto

@Suite("KeyNavCoordinator — ⌘A")
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

    @Test("⌘A in the search field selects the field's text, not the clips")
    func whenSearchFieldHasFocus_thenCommandASelectsItsText() throws {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        textView.string = "invoice"
        window.contentView?.addSubview(textView)
        #expect(window.makeFirstResponder(textView))
        let coordinator = KeyNavCoordinator()
        coordinator.isOverlayVisible = true
        coordinator.hostWindow = window
        coordinator.isSearchActive = true
        var selectedClips = false
        coordinator.onSelectAll = { selectedClips = true }
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "a",
            charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0
        ))

        let result = coordinator.handle(event)

        #expect(result == nil, "the shelf panel has no Edit menu to take ⌘A, so the monitor must consume it")
        #expect(textView.selectedRange() == NSRange(location: 0, length: 7))
        #expect(!selectedClips)
    }
}
