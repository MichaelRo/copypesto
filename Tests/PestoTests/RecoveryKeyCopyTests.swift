// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("The recovery key copied from the backup sheet leaves the pasteboard", .serialized)
    @MainActor
    final class RecoveryKeyCopyTests {
        private let state = AppState()

        init() {
            state.secretClearDelay = .milliseconds(50)
            AppPasteboard.general.clearContents()
        }

        private var boardTypes: [String] {
            (AppPasteboard.general.types ?? []).map(\.rawValue)
        }

        @Test("the recovery key is copied concealed")
        func whenTheRecoveryKeyIsCopied_thenItIsMarked() {
            state.copyRecoveryKey("PESTO-ABCD-EFGH")

            #expect(PasteboardProtection.isProtected(types: boardTypes))
            #expect(AppPasteboard.general.string(forType: .string) == "PESTO-ABCD-EFGH")
        }

        @Test("the recovery key leaves the pasteboard after the delay if nothing else was copied")
        func whenTheRecoveryKeyIsCopied_thenItIsClearedAfterTheDelay() async throws {
            state.copyRecoveryKey("PESTO-ABCD-EFGH")

            try await Task.sleep(for: .milliseconds(400))

            #expect(AppPasteboard.general.string(forType: .string) == nil)
        }

        @Test("a copy made after the recovery key is left alone")
        func whenSomethingElseIsCopiedAfterTheKey_thenItStays() async throws {
            state.secretClearDelay = .milliseconds(150)
            state.copyRecoveryKey("PESTO-ABCD-EFGH")
            AppPasteboard.general.clearContents()
            AppPasteboard.general.setString("a newer copy", forType: .string)

            try await Task.sleep(for: .milliseconds(500))

            #expect(AppPasteboard.general.string(forType: .string) == "a newer copy")
        }
    }
}
