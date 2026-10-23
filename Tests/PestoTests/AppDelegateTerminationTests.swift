// SPDX-License-Identifier: MIT
import AppKit
import Testing
@testable import Pesto

@Suite("AppDelegate — termination policy")
@MainActor
struct AppDelegateTerminationTests {
    @Test("closing the last window must not terminate a menu-bar accessory app")
    func whenLastWindowCloses_thenAppKeepsRunning() {
        // Regression: closing Settings quit the whole app, taking the menu-bar item, hotkey
        // and pasteboard watcher with it.
        let delegate = AppDelegate()
        #expect(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp) == false)
    }
}
