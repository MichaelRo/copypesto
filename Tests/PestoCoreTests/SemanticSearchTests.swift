// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Search by meaning: the query side")
struct SemanticSearchTests {
    private func vector(_ values: [Float]) -> Data {
        values.withUnsafeBytes { Data($0) }
    }

    @Test("only a plain query longer than eight characters asks for meaning")
    func whenQueryIsShortOrASourceFilter_thenItDoesNotAskForMeaning() {
        #expect(SemanticSearch.asksForMeaning("quarterly numbers"))
        #expect(SemanticSearch.asksForMeaning("  quarterly numbers  "))
        #expect(!SemanticSearch.asksForMeaning("quarters"))
        #expect(!SemanticSearch.asksForMeaning("@Safari quarterly numbers"))
        #expect(!SemanticSearch.asksForMeaning("short"))
    }

    @Test("clips at or above the threshold rank nearest first, and a clip with no vector is left out")
    func whenRanking_thenNearestFirstAndTheFarOnesAreLeftOut() {
        let near = UUID(), nearer = UUID(), far = UUID(), none = UUID()
        let ranked = SemanticSearch.rank(
            queryEmbedding: vector([1, 0]),
            candidates: [
                (near, vector([1, 0.5])), (far, vector([0, 1])), (nearer, vector([1, 0.1])), (none, nil)
            ]
        )
        #expect(ranked == [nearer, near])
    }

    @Test("meaning matches follow the text matches, once each, and only where the scope allows them")
    func whenMerging_thenTextMatchesLeadAndAllowedOnesFollow() {
        let first = UUID(), second = UUID(), third = UUID(), outside = UUID()
        let merged = SemanticSearch.merged(
            textMatches: [first, second], byMeaning: [second, outside, third],
            allowed: [first, second, third]
        )
        #expect(merged == [first, second, third])
    }
}
