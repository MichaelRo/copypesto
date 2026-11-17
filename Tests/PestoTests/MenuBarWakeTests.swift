// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("MenuBarWake", .serialized)
    @MainActor
    final class MenuBarWakeTests {
        @Test("menuBarIsFull or hidden icon causes applicationShouldHandleReopen to open Settings")
        func whenMenuBarIconUnavailable_thenReopenOpensSettings() {
            let delegate = AppDelegate()
            // With no statusItem installed, menuBarIconIsOnScreen is false.
            #expect(!delegate.menuBarIconIsOnScreen)

            let handled = delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false)
            #expect(handled)
            #expect(delegate.settingsWindow != nil)
            delegate.settingsWindow?.close()
            delegate.settingsWindow = nil
        }

        @Test("PESTO_UITEST_MENUBAR_FULL=1 sets menuBarIsFull in RuntimeConfiguration")
        func whenMenuBarFullEnvSet_thenRuntimeConfigurationMarksMenuBarFull() {
            let config = RuntimeConfiguration.parse(
                arguments: ["-UITestMode"],
                environment: ["PESTO_UITEST_MENUBAR_FULL": "1"],
                allowsTestHooks: true
            )
            #expect(config.menuBarIsFull)
        }
    }
}
