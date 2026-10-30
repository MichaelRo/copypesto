// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("Copy Result keeps a protected answer protected", .serialized)
    @MainActor
    final class AIResultCopyTests {
        private let state = AppState()

        init() {
            AppPasteboard.general.clearContents()
        }

        private var boardTypes: [String] {
            (AppPasteboard.general.types ?? []).map(\.rawValue)
        }

        @Test("an answer made from a shown secret is copied concealed")
        func whenAnswerIsProtected_thenCopyIsMarkedConcealed() {
            let result = AIResult(action: .summarize, sourcePreview: "s", result: "4242 4242", isProtected: true)

            state.copyAIResult(result)

            #expect(AppPasteboard.general.string(forType: .string) == "4242 4242")
            #expect(PasteboardProtection.isProtected(types: boardTypes))
        }

        @Test("an ordinary answer is copied without the marker")
        func whenAnswerIsOrdinary_thenCopyIsUnmarked() {
            state.copyAIResult(AIResult(action: .summarize, sourcePreview: "s", result: "lunch at noon"))

            #expect(AppPasteboard.general.string(forType: .string) == "lunch at noon")
            #expect(!PasteboardProtection.isProtected(types: boardTypes))
        }
    }
}
