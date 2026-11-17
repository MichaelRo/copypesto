// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("PasteboardAccessHosted", .serialized)
    @MainActor
    final class PasteboardAccessHostedTests {
        private let limitedTitle = "Clipboard Access Limited — Open Settings…"

        @Test("status menu shows limited-access item for prompting and blocked, and hides it for allowed")
        func whenPromptingOrBlocked_thenStatusMenuShowsWarning() {
            let delegate = AppDelegate()
            let menu = NSMenu()

            delegate.updateStatusMenu(menu, pasteboardAccess: .blocked, checksPasteboardAccess: true)
            #expect(menu.items.contains { $0.title == limitedTitle })

            delegate.updateStatusMenu(menu, pasteboardAccess: .prompting, checksPasteboardAccess: true)
            #expect(menu.items.contains { $0.title == limitedTitle })

            delegate.updateStatusMenu(menu, pasteboardAccess: .allowed, checksPasteboardAccess: true)
            #expect(!menu.items.contains { $0.title == limitedTitle })

            delegate.updateStatusMenu(menu, pasteboardAccess: .notDecided, checksPasteboardAccess: true)
            #expect(!menu.items.contains { $0.title == limitedTitle })
        }

        @Test("PESTO_UITEST_PASTEBOARD_ACCESS parses all four access states in UI-test mode")
        func whenUITestEnvSet_thenRuntimeConfigurationParsesPasteboardAccess() {
            let cases: [(String, PasteboardCaptureAccess)] = [
                ("allowed", .allowed),
                ("prompting", .prompting),
                ("notDecided", .notDecided),
                ("blocked", .blocked)
            ]
            for (raw, expected) in cases {
                let config = RuntimeConfiguration.parse(
                    arguments: ["-UITestMode"],
                    environment: ["PESTO_UITEST_PASTEBOARD_ACCESS": raw],
                    allowsTestHooks: true
                )
                #expect(config.pasteboardAccess == expected)
                #expect(expected.needsAttention == (expected == .prompting || expected == .blocked))
            }
        }
    }
}
