// SPDX-License-Identifier: MIT
import AppKit
import Testing
@testable import Pesto

private final class ProbeMenu: NSMenu {
    var cancelTrackingCount = 0

    override func cancelTracking() {
        cancelTrackingCount += 1
        super.cancelTracking()
    }
}

@Suite("ContextMenuKeyBridge")
@MainActor
struct ContextMenuKeyBridgeTests {
    private func makeMenuWindowWithFieldEditor() throws -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let field = NSTextField(frame: NSRect(x: 12, y: 12, width: 200, height: 24))
        window.contentView?.addSubview(field)
        window.orderBack(nil)
        window.makeFirstResponder(field)
        _ = try #require(window.firstResponder as? NSTextView)
        return window
    }

    private func keyEvent(
        keyCode: UInt16,
        characters: String = "",
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
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    @Test("Escape while a field editor is active cancels the active menu and consumes the event")
    func whenFieldEditorActiveAndEscape_thenCancelsMenuAndConsumesEvent() throws {
        let window = try makeMenuWindowWithFieldEditor()
        defer { window.close() }
        let menu = ProbeMenu()
        let bridge = ContextMenuKeyBridge()
        bridge.beginTracking(menu: menu)
        defer { bridge.stop() }
        #expect(bridge.isMonitoring)

        let escape = try keyEvent(keyCode: 53, characters: "\u{1b}", in: window)
        let result = bridge.handle(escape)

        #expect(result == nil)
        #expect(menu.cancelTrackingCount == 1)
    }

    @Test("Down Arrow while a field editor is active resigns first responder and lets the menu take focus")
    func whenFieldEditorActiveAndDownArrow_thenResignsFirstResponderAndPassesThrough() throws {
        let window = try makeMenuWindowWithFieldEditor()
        defer { window.close() }
        let menu = ProbeMenu()
        let bridge = ContextMenuKeyBridge()
        bridge.beginTracking(menu: menu)
        defer { bridge.stop() }

        let downArrow = try keyEvent(keyCode: 125, in: window)
        let result = bridge.handle(downArrow)

        #expect(result === downArrow)
        #expect(!(window.firstResponder is NSTextView))
        #expect(!(window.firstResponder is NSTextField))
        #expect(menu.cancelTrackingCount == 0)
    }

    @Test("regular typing in the field editor passes through untouched without resigning or cancelling")
    func whenFieldEditorActiveAndTyping_thenPassesThroughUntouched() throws {
        let window = try makeMenuWindowWithFieldEditor()
        defer { window.close() }
        let menu = ProbeMenu()
        let bridge = ContextMenuKeyBridge()
        bridge.beginTracking(menu: menu)
        defer { bridge.stop() }

        let letterA = try keyEvent(keyCode: 0, characters: "a", in: window)
        let result = bridge.handle(letterA)

        #expect(result === letterA)
        #expect(window.firstResponder is NSTextView)
        #expect(menu.cancelTrackingCount == 0)
    }

    @Test("Escape and Down Arrow pass through untouched when no field editor is active")
    func whenNoFieldEditorActive_thenEscapeAndDownArrowPassThrough() throws {
        let window = try makeMenuWindowWithFieldEditor()
        defer { window.close() }
        window.makeFirstResponder(nil)
        #expect(!(window.firstResponder is NSTextView))

        let menu = ProbeMenu()
        let bridge = ContextMenuKeyBridge()
        bridge.beginTracking(menu: menu)
        defer { bridge.stop() }

        let escape = try keyEvent(keyCode: 53, characters: "\u{1b}", in: window)
        let downArrow = try keyEvent(keyCode: 125, in: window)

        #expect(bridge.handle(escape) === escape)
        #expect(bridge.handle(downArrow) === downArrow)
        #expect(menu.cancelTrackingCount == 0)
    }

    @Test("endTracking removes the monitor and stops intercepting keys")
    func whenEndTracking_thenStopsMonitoringAndPassesKeysThrough() throws {
        let window = try makeMenuWindowWithFieldEditor()
        defer { window.close() }
        let menu = ProbeMenu()
        let bridge = ContextMenuKeyBridge()
        bridge.beginTracking(menu: menu)
        #expect(bridge.isMonitoring)

        bridge.endTracking(menu: menu)
        #expect(!bridge.isMonitoring)

        let escape = try keyEvent(keyCode: 53, characters: "\u{1b}", in: window)
        let downArrow = try keyEvent(keyCode: 125, in: window)
        #expect(bridge.handle(escape) === escape)
        #expect(bridge.handle(downArrow) === downArrow)
        #expect(window.firstResponder is NSTextView)
        #expect(menu.cancelTrackingCount == 0)
    }
}
