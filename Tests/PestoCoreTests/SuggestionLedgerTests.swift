// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Suggestion ledger")
struct SuggestionLedgerTests {
    @Test("empty ledger initializes with zero shows and no silences")
    func whenEmpty_thenNoShowsOrSilences() {
        let ledger = SuggestionLedger(serialized: "")
        let id = UUID()
        #expect(ledger.shows(.shortcutOffer, id) == 0)
        #expect(!ledger.isSilenced(id))
        #expect(!ledger.isResolved(.shortcutOffer, id))
        #expect(ledger.serialized.isEmpty)
    }

    @Test("noting shows increments count and preserves across round trip")
    func whenRoundTripped_thenEqual() {
        var ledger = SuggestionLedger(serialized: "")
        let id = UUID()
        ledger.noteShown(.shortcutOffer, id)
        ledger.noteShown(.shortcutOffer, id)
        #expect(ledger.shows(.shortcutOffer, id) == 2)

        let reloaded = SuggestionLedger(serialized: ledger.serialized)
        #expect(reloaded.shows(.shortcutOffer, id) == 2)
    }

    @Test("when over two hundred lines, oldest entries are dropped")
    func whenOverTwoHundredLines_thenOldestDropped() {
        var ledger = SuggestionLedger(serialized: "")
        let firstID = UUID()
        ledger.noteShown(.shortcutOffer, firstID)

        for _ in 0..<205 {
            ledger.noteShown(.snippet, UUID())
        }

        #expect(ledger.shows(.shortcutOffer, firstID) == 0)
    }

    @Test("garbage lines are skipped without crashing")
    func whenGarbageLine_thenSkippedNotCrash() {
        let id = UUID()
        let corrupted = "garbage\nnot-valid-line|123\nshortcutOffer|\(id.uuidString)|2|accepted\n\n"
        let ledger = SuggestionLedger(serialized: corrupted)
        #expect(ledger.shows(.shortcutOffer, id) == 2)
        #expect(ledger.isResolved(.shortcutOffer, id))
    }

    @Test("when resolved as accepted, it is reported resolved")
    func whenResolved_thenReported() {
        var ledger = SuggestionLedger(serialized: "")
        let id = UUID()
        ledger.resolve(.shortcutOffer, id, as: .accepted)
        #expect(ledger.isResolved(.shortcutOffer, id))
        #expect(!ledger.isSilenced(id))
    }

    @Test("when declined, clip is silenced for every kind unless re-armed")
    func whenDeclined_thenSilencedUntilDoubled() {
        var ledger = SuggestionLedger(serialized: "")
        let id = UUID()
        ledger.resolve(.shortcutOffer, id, as: .declined(atPasteCount: 6))
        #expect(ledger.isSilenced(id, currentPastes: 6))
        #expect(ledger.isSilenced(id, currentPastes: 11))
        #expect(!ledger.isSilenced(id, currentPastes: 12)) // Doubled!
    }

    @Test("when three ignored shows occur, clip is muted")
    func whenIgnoredThreeShows_thenMuted() {
        var ledger = SuggestionLedger(serialized: "")
        let id = UUID()
        ledger.noteShown(.shortcutOffer, id)
        ledger.noteShown(.shortcutOffer, id)
        #expect(!ledger.isSilenced(id))
        ledger.noteShown(.shortcutOffer, id)
        #expect(ledger.isSilenced(id))
    }
}
