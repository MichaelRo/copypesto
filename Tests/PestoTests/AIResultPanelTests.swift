// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("AIResultPanel close button and presentation", .serialized)
    @MainActor
    final class AIResultPanelTests {
        private func sendClick(to window: NSWindow, at point: NSPoint) throws {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try #require(NSEvent.mouseEvent(
                    with: type,
                    location: point,
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 1,
                    pressure: 1
                ))
                window.sendEvent(event)
            }
        }

        @Test("clicking the top-trailing X close button triggers onClose instead of window drag")
        func whenClickingCloseButton_thenOnCloseFires() async throws {
            let controller = AIResultPanelController()
            var closed = 0
            let result = AIResult(
                action: .toneConcise,
                sourcePreview: "Long draft message",
                result: "Short reply."
            )
            controller.showResult(
                result,
                onClose: {
                    closed += 1
                    controller.hide()
                },
                onPaste: {},
                onCopy: {}
            )
            defer { controller.hide() }

            let panel = try #require(controller.panel)
            let contentView = try #require(panel.contentView)
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            contentView.layoutSubtreeIfNeeded()
            panel.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(150))

            // Close button sits 16pt from trailing edge, 14pt from top, size 28x28 -> center at (width - 30, height -
            // 28).
            let closePoint = NSPoint(x: contentView.bounds.width - 30, y: contentView.bounds.height - 28)
            try sendClick(to: panel, at: closePoint)
            try await Task.sleep(for: .milliseconds(150))

            #expect(closed == 1)
            #expect(controller.panel == nil)
        }

        @Test("close button hit exclusion respects LTR/RTL while header center stays draggable")
        func whenCheckingCloseButtonZone_thenExcludesTrailingCornerAndKeepsHeaderCenterDraggable() {
            let ltrView = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 220))
            ltrView.userInterfaceLayoutDirection = .leftToRight
            #expect(AIResultPanel.isInCloseButtonZone(NSPoint(x: 310, y: 192), in: ltrView))
            #expect(!AIResultPanel.isInCloseButtonZone(NSPoint(x: 170, y: 198), in: ltrView))
            #expect(!AIResultPanel.isInCloseButtonZone(NSPoint(x: 24, y: 192), in: ltrView))
            #expect(!AIResultPanel.isInCloseButtonZone(NSPoint(x: 310, y: 120), in: ltrView))

            let rtlView = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 220))
            rtlView.userInterfaceLayoutDirection = .rightToLeft
            #expect(AIResultPanel.isInCloseButtonZone(NSPoint(x: 28, y: 192), in: rtlView))
            #expect(!AIResultPanel.isInCloseButtonZone(NSPoint(x: 310, y: 192), in: rtlView))
            #expect(!AIResultPanel.isInCloseButtonZone(NSPoint(x: 170, y: 198), in: rtlView))
        }
    }
}
