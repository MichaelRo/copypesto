// SPDX-License-Identifier: MIT
import AppKit
import Testing
@testable import Pesto

@Suite("The focused card's view for ⌘K")
@MainActor
struct FocusedCardAnchorTests {
    private func windowWithView() -> (NSWindow, NSView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless],
            backing: .buffered, defer: false
        )
        let live = NSView(frame: NSRect(x: 10, y: 10, width: 100, height: 100))
        window.contentView?.addSubview(live)
        return (window, live)
    }

    @Test("a view SwiftUI makes later and throws away does not hide the live one")
    func whenAThrowawayViewIsRegisteredAfter_thenTheLiveOneIsKept() {
        let (window, live) = windowWithView()
        let anchor = FocusedCardAnchor()
        anchor.register(live)

        autoreleasepool { anchor.register(NSView()) }

        #expect(anchor.liveView === live)
        #expect(anchor.hasView)
        #expect(window.contentView != nil)
    }

    @Test("a view that is in no window is not something to open a menu on")
    func whenNoViewIsInAWindow_thenNone() {
        let anchor = FocusedCardAnchor()

        anchor.register(NSView())

        #expect(anchor.liveView == nil)
        #expect(!anchor.hasView)
    }

    @Test("when two views are live, the one registered last is the focused card")
    func whenTwoAreLive_thenTheNewest() {
        let (_, first) = windowWithView()
        let (_, second) = windowWithView()
        let anchor = FocusedCardAnchor()

        anchor.register(first)
        anchor.register(second)

        #expect(anchor.liveView === second)
    }
}
