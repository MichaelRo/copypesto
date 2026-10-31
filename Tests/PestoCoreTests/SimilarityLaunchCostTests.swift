// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

/// What noticing look-alike clips costs outside the ingest path (ADR 0017): opening every stored signature at launch,
/// and
/// the suggestion facts the shelf asks for when it opens. It measures and emits; the budgets are generous because the
/// test store is in memory and runs unoptimized. Run optimized for real numbers: `swift test -Xswiftc -O --filter
/// SimilarityLaunchCost`.
@Suite("Similarity launch cost")
struct SimilarityLaunchCostTests {
    private let clipCount = 2000

    private func capture(_ text: String) -> PasteboardCapture {
        PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
            contentHash: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        )
    }

    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    @Test("opening 2,000 stored signatures and asking for the suggestion facts stay far below a frame budget each")
    func whenManyClips_thenLoadAndFactsAreCheap() async throws {
        let container = try ModelContainerSetup.makeInMemory()
        let service = StorageService(modelContainer: container)
        for index in 0..<clipCount {
            let family = index % 40
            let text = "Message \(family) alpha beta gamma delta epsilon zeta eta theta iota kappa lambda "
                + "to \(index) and the shared closing words of family \(family) that make it long enough to sign"
            try await service.ingest(capture(text))
        }
        let clock = ContinuousClock()

        await service.dropSimilarityIndex()
        let load = try await clock.measure { try await service.loadSimilarityIndex() }
        let facts = try await clock.measure { _ = try await service.shelfSuggestionFacts(unavailableSlots: []) }

        let loadText = String(format: "%.1f", milliseconds(load))
        let factsText = String(format: "%.1f", milliseconds(facts))
        let line = "PERF similarity load of \(clipCount) signatures: \(loadText) ms; "
            + "suggestion facts: \(factsText) ms\n"
        FileHandle.standardError.write(Data(line.utf8))
        #expect(milliseconds(load) < 4000)
        #expect(milliseconds(facts) < 1000)
    }
}
