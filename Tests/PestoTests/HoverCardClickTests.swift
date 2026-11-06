// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import Testing
@testable import Pesto

@Suite("A button in the hover card panel", .serialized)
@MainActor
struct HoverCardClickTests {
    private func click(_ panel: HoverCardPanel, at point: NSPoint) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ) else { return }
            panel.sendEvent(event)
        }
    }

    @Test("a click lands in a panel that is never key, so Copy Text can be pressed")
    func whenClickedInTheNeverKeyPanel_thenTheButtonFires() async throws {
        let panel = HoverCardPanel()
        var copies = 0
        panel.hosting.setPestoRoot(
            HoverCardCopyButton(quiet: .gray, copy: {
                copies += 1
                return true
            })
            .padding(16)
            .fixedSize()
        )
        panel.ignoresMouseEvents = false
        panel.orderFront(nil)
        defer { panel.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(300))
        let size = NSSize(width: 200, height: 70)
        panel.setContentSize(size)
        panel.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        click(panel, at: NSPoint(x: size.width / 2, y: size.height / 2))
        try await Task.sleep(for: .milliseconds(200))

        #expect(!panel.isKeyWindow)
        #expect(copies == 1)
    }
}
