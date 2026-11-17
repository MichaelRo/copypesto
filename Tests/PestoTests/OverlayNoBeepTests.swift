// SPDX-License-Identifier: MIT
import AppKit
import ObjectiveC.runtime
import Testing
@testable import Pesto

@MainActor
private enum NoBeepSpy {
    static var responderNoResponderCount = 0
    static var windowNoResponderCount = 0
    static var textViewNoopCount = 0
    static var terminateCount = 0

    static func reset() {
        responderNoResponderCount = 0
        windowNoResponderCount = 0
        textViewNoopCount = 0
        terminateCount = 0
    }

    static var totalBeeps: Int {
        responderNoResponderCount + windowNoResponderCount + textViewNoopCount
    }
}

private extension NSResponder {
    @objc
    func pesto_spy_responderNoResponder(for event: NSEvent) {
        MainActor.assumeIsolated { NoBeepSpy.responderNoResponderCount += 1 }
        pesto_spy_responderNoResponder(for: event)
    }
}

private extension NSWindow {
    @objc
    func pesto_spy_windowNoResponder(for event: NSEvent) {
        MainActor.assumeIsolated { NoBeepSpy.windowNoResponderCount += 1 }
        pesto_spy_windowNoResponder(for: event)
    }
}

private extension NSTextView {
    @objc
    func pesto_spy_doCommand(by selector: Selector) {
        if selector == Selector(("noop:")) {
            MainActor.assumeIsolated { NoBeepSpy.textViewNoopCount += 1 }
            return
        }
        pesto_spy_doCommand(by: selector)
    }
}

private extension NSApplication {
    @objc
    func pesto_spy_terminate(_: Any?) {
        MainActor.assumeIsolated { NoBeepSpy.terminateCount += 1 }
    }
}

extension HostedGlobals {
    private struct SwizzlePair {
        let cls: AnyClass
        let original: Selector
        let replacement: Selector
    }

    @Suite("Live OverlayPanel routes keys through NSApp.sendEvent without beeps", .serialized)
    @MainActor
    final class OverlayNoBeepTests {
        private func swizzle(_ cls: AnyClass, original: Selector, replacement: Selector) throws {
            let m1 = try #require(class_getInstanceMethod(cls, original))
            let m2 = try #require(class_getInstanceMethod(cls, replacement))
            method_exchangeImplementations(m1, m2)
        }

        private func installSwizzles() throws -> () -> Void {
            let pairs = [
                SwizzlePair(
                    cls: NSResponder.self,
                    original: #selector(NSResponder.noResponder(for:)),
                    replacement: #selector(NSResponder.pesto_spy_responderNoResponder(for:))
                ),
                SwizzlePair(
                    cls: NSWindow.self,
                    original: #selector(NSWindow.noResponder(for:)),
                    replacement: #selector(NSWindow.pesto_spy_windowNoResponder(for:))
                ),
                SwizzlePair(
                    cls: NSTextView.self,
                    original: #selector(NSTextView.doCommand(by:)),
                    replacement: #selector(NSTextView.pesto_spy_doCommand(by:))
                ),
                SwizzlePair(
                    cls: NSApplication.self,
                    original: #selector(NSApplication.terminate(_:)),
                    replacement: #selector(NSApplication.pesto_spy_terminate(_:))
                )
            ]
            for pair in pairs {
                try swizzle(pair.cls, original: pair.original, replacement: pair.replacement)
            }
            return { [self] in
                for pair in pairs.reversed() {
                    try? swizzle(pair.cls, original: pair.original, replacement: pair.replacement)
                }
            }
        }

        private func sendKey(
            code: UInt16,
            flags: NSEvent.ModifierFlags,
            chars: String = "",
            unmodified: String = "",
            to window: NSWindow
        ) throws {
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                characters: chars, charactersIgnoringModifiers: unmodified,
                isARepeat: false, keyCode: code
            ))
            NSApp.sendEvent(event)
        }

        private func waitForSearchFocus(in window: NSWindow) async {
            for _ in 0..<20 {
                if window.firstResponder is NSTextView { return }
                try? await Task.sleep(for: .milliseconds(25))
            }
        }

        @Test("unowned keys, ⌘W and ⌘Q behave without beeps in both Grid mode and Search mode")
        func whenKeysRoutedThroughApp_thenZeroBeepsInGridAndSearchModes() async throws {
            NoBeepSpy.reset()
            let restoreSwizzles = try installSwizzles()
            defer {
                restoreSwizzles()
                NoBeepSpy.reset()
            }

            let state = AppState()
            let controller = OverlayWindowController(appState: state)
            state.isOverlayVisible = true
            controller.show()
            NSApp.activate(ignoringOtherApps: true)
            controller.overlayWindow.makeKeyAndOrderFront(nil)
            defer {
                state.isOverlayVisible = false
                controller.hide()
            }
            try await Task.sleep(for: .milliseconds(250))

            let window = controller.overlayWindow

            // Grid mode
            state.isSearchActive = false
            try await Task.sleep(for: .milliseconds(50))
            try sendKey(code: 1, flags: .command, chars: "s", unmodified: "s", to: window)
            try sendKey(code: 29, flags: .command, chars: "0", unmodified: "0", to: window)
            try sendKey(code: 0, flags: .control, chars: "\u{01}", unmodified: "a", to: window)
            try sendKey(code: 4, flags: .command, chars: "h", unmodified: "h", to: window)
            #expect(NoBeepSpy.totalBeeps == 0)

            try sendKey(code: 13, flags: .command, chars: "w", unmodified: "w", to: window)
            #expect(!state.isOverlayVisible)
            #expect(NoBeepSpy.totalBeeps == 0)

            state.isOverlayVisible = true
            controller.show()
            controller.overlayWindow.makeKeyAndOrderFront(nil)
            try await Task.sleep(for: .milliseconds(150))

            try sendKey(code: 12, flags: .command, chars: "q", unmodified: "q", to: window)
            #expect(NoBeepSpy.terminateCount == 1)
            #expect(NoBeepSpy.totalBeeps == 0)

            // Search mode
            state.isSearchActive = true
            await waitForSearchFocus(in: window)
            try sendKey(code: 1, flags: .command, chars: "s", unmodified: "s", to: window)
            try sendKey(code: 29, flags: .command, chars: "0", unmodified: "0", to: window)
            try sendKey(code: 0, flags: .control, chars: "\u{01}", unmodified: "a", to: window)
            try sendKey(code: 116, flags: [], to: window)
            try sendKey(code: 4, flags: .command, chars: "h", unmodified: "h", to: window)
            #expect(NoBeepSpy.totalBeeps == 0)

            try sendKey(code: 13, flags: .command, chars: "w", unmodified: "w", to: window)
            #expect(!state.isOverlayVisible)
            #expect(NoBeepSpy.totalBeeps == 0)

            state.isOverlayVisible = true
            state.isSearchActive = true
            controller.show()
            controller.overlayWindow.makeKeyAndOrderFront(nil)
            await waitForSearchFocus(in: window)

            try sendKey(code: 12, flags: .command, chars: "q", unmodified: "q", to: window)
            #expect(NoBeepSpy.terminateCount == 2)
            #expect(NoBeepSpy.totalBeeps == 0)
        }
    }
}
