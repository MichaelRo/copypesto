// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Suggestion statistics")
struct SuggestionStatsTests {
    @Test("shown, accepted and declined are counted per kind from the ledger")
    func whenLedgerHasOutcomes_thenCountedPerKind() {
        var ledger = SuggestionLedger(serialized: "")
        let a = UUID(), b = UUID(), c = UUID()
        ledger.noteShown(.snippet, a, pastes: 0, now: .now)
        ledger.noteShown(.snippet, b, pastes: 0, now: .now)
        ledger.noteShown(.snippet, c, pastes: 0, now: .now)
        ledger.resolve(.snippet, a, as: .accepted)
        ledger.resolve(.snippet, b, as: .declined(atPasteCount: 1))
        ledger.noteShown(.shortcutOffer, a, pastes: 0, now: .now)
        ledger.resolve(.shortcutOffer, a, as: .accepted)

        let stats = SuggestionStats(ledger: ledger)

        #expect(stats.row(for: .snippet) == SuggestionStats.Row(kind: .snippet, shown: 3, accepted: 1, declined: 1))
        #expect(stats.row(for: .shortcutOffer)?.accepted == 1)
        #expect(stats.row(for: .shortcutRelease) == nil)
    }

    @Test("the summary is plain text with numbers only, never a clip id or a clip's text")
    func whenSummarized_thenNumbersOnly() {
        var ledger = SuggestionLedger(serialized: "")
        let id = UUID()
        ledger.noteShown(.snippet, id, pastes: 0, now: .now)
        ledger.resolve(.snippet, id, as: .accepted)

        let summary = SuggestionStats(ledger: ledger).summary

        #expect(summary.contains("Snippets: shown 1, accepted 1, declined 0"))
        #expect(!summary.contains(id.uuidString))
    }

    @Test("an empty ledger says so")
    func whenNothingShown_thenSaysSo() {
        #expect(SuggestionStats(ledger: SuggestionLedger(serialized: "")).summary == "No suggestions shown yet.")
    }
}
