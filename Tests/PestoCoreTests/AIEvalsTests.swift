// SPDX-License-Identifier: MIT
import Foundation
import Testing
#if canImport(FoundationModels)
import FoundationModels
#endif
#if canImport(Evaluations)
import Evaluations
#endif
@testable import PestoCore

@Suite("AI chunking evaluations")
struct AIEvalsTests {
    @Test("chunker splits long text on paragraph or sentence boundaries within budget")
    func whenLongText_thenSplitsWithinBudget() {
        let paragraph = "Swift concurrency uses structured tasks and actors to isolate mutable state. "
        let longText = String(repeating: paragraph + "\n\n", count: 40)
        let result = AIChunker.parts(of: longText, budget: 350)
        #expect(result.parts.count > 1)
        #expect(!result.isCut)
        for part in result.parts {
            #expect(part.text.count <= 350)
            #expect(part.start >= 1 && part.end >= part.start)
        }
    }

    @Test("the real on-device model evaluates chunked summaries", .enabled(if: Self.modelAvailable))
    func whenModelAvailable_thenEvaluatesChunkedSummary() async throws {
        guard #available(macOS 26, *) else { return }
        let doc = (1...12).map { index in
            "Section \(index): Pesto keeps history encrypted on disk and never uploads clips."
        }.joined(separator: "\n\n")
        let chunked = AIChunker.parts(of: doc, budget: 400)
        #expect(chunked.parts.count >= 2)

        let client = AppleIntelligenceClient()
        var summaries: [String] = []
        for part in chunked.parts {
            let reply = try await client.complete(
                system: "Summarize the excerpt in one short sentence.",
                userMessage: part.text
            )
            let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(!trimmed.isEmpty)
            summaries.append(trimmed)
        }
        #expect(summaries.count == chunked.parts.count)
    }

    static var modelAvailable: Bool {
        #if canImport(FoundationModels) && arch(arm64)
        guard #available(macOS 26, *) else { return false }
        return SystemLanguageModel.default.availability == .available
        #else
        return false
        #endif
    }
}
