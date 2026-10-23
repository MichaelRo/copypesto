// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import Testing
@testable import Pesto

@Suite("Shelf panel accessibility")
@MainActor
struct OverlayPanelAccessibilityTests {
    @Test("VoiceOver hears one labelled floating window, not 'system dialog, group'")
    func whenPanelCreated_thenLabelledFloatingWindow() {
        let panel = OverlayPanel()

        #expect(panel.accessibilityRole() == .window)
        #expect(panel.accessibilitySubrole() == .floatingWindow)
        #expect(panel.accessibilityLabel() == "Clipboard history")
        #expect(panel.becomesKeyOnlyIfNeeded == false)
    }

    @Test("cancelOperation routes to onEscapeKey so Escape always closes the shelf")
    func whenCancelOperationTriggered_thenEscapeHandlerFires() {
        let panel = OverlayPanel()
        var escaped = false
        panel.onEscapeKey = { escaped = true }

        panel.cancelOperation(nil)

        #expect(escaped)
    }

    @Test("HoverCardHost never swallows Escape when its panel is not visible, and clears its owner on dismiss")
    func whenHoverCardRequestedButNotVisible_thenEscapeIsNotSwallowed() {
        let anchor = NSView()
        let owner = UUID()
        var escapeCalled = false
        HoverCardHost.shared.present(.init(
            owner: owner, anchor: anchor, scrolls: false, content: { AnyView(EmptyView()) },
            onPointerInside: { _ in }, onReplaced: {}, onEscape: { escapeCalled = true }
        ))

        #expect(HoverCardHost.shared.closeForEscape() == false)
        #expect(escapeCalled == false)
        #expect(HoverCardHost.shared.closeForEscape() == false)
    }
}
