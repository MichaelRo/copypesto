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
        #expect(!ledger.isBlocked(.shortcutOffer, id, pastes: 0, now: .now))
        #expect(ledger.serialized.isEmpty)
    }

    @Test("noting shows increments count and preserves across round trip")
    func whenRoundTripped_thenEqual() {
        var ledger = SuggestionLedger(serialized: "")
        let id = UUID()
        ledger.noteShown(.shortcutOffer, id, pastes: 0, now: .now)
        ledger.noteShown(.shortcutOffer, id, pastes: 0, now: .now)
        #expect(ledger.shows(.shortcutOffer, id) == 2)

        let reloaded = SuggestionLedger(serialized: ledger.serialized)
        #expect(reloaded.shows(.shortcutOffer, id) == 2)
    }

    @Test("when over two hundred lines, oldest entries are dropped")
    func whenOverTwoHundredLines_thenOldestDropped() {
        var ledger = SuggestionLedger(serialized: "")
        let firstID = UUID()
        ledger.noteShown(.shortcutOffer, firstID, pastes: 0, now: .now)

        for _ in 0..<205 {
            ledger.noteShown(.snippet, UUID(), pastes: 0, now: .now)
        }

        #expect(ledger.shows(.shortcutOffer, firstID) == 0)
    }

    @Test("garbage lines are skipped without crashing")
    func whenGarbageLine_thenSkippedNotCrash() {
        let id = UUID()
        let corrupted = "garbage\nnot-valid-line|123\nshortcutOffer|\(id.uuidString)|2|accepted\n\n"
        let ledger = SuggestionLedger(serialized: corrupted)
        #expect(ledger.shows(.shortcutOffer, id) == 2)
        #expect(ledger.isBlocked(.shortcutOffer, id, pastes: 0, now: .now))
    }

    @Test("when resolved as accepted, it is reported resolved")
    func whenResolved_thenReported() {
        var ledger = SuggestionLedger(serialized: "")
        let id = UUID()
        ledger.resolve(.shortcutOffer, id, as: .accepted)
        #expect(ledger.isBlocked(.shortcutOffer, id, pastes: 0, now: .now))
    }

    @Test("when declined, the kind waits for doubled pastes and thirty days")
    func whenDeclined_thenBlockedUntilDoubledAndThirtyDays() {
        var ledger = SuggestionLedger(serialized: "")
        let id = UUID()
        let declinedOn = Date(timeIntervalSince1970: 1_000_000)
        let afterThirty = declinedOn.addingTimeInterval(30 * 86_400)
        ledger.resolve(.shortcutOffer, id, as: .declined(atPasteCount: 6), now: declinedOn)
        #expect(ledger.isBlocked(.shortcutOffer, id, pastes: 12, now: declinedOn.addingTimeInterval(29 * 86_400)))
        #expect(ledger.isBlocked(.shortcutOffer, id, pastes: 11, now: afterThirty))
        #expect(!ledger.isBlocked(.shortcutOffer, id, pastes: 12, now: afterThirty))
    }

    @Test("when declined twice, the kind is blocked for good")
    func whenDeclinedTwice_thenBlockedForever() {
        var ledger = SuggestionLedger(serialized: "")
        let id = UUID()
        let first = Date(timeIntervalSince1970: 1_000_000)
        let later = first.addingTimeInterval(60 * 86_400)
        ledger.resolve(.shortcutOffer, id, as: .declined(atPasteCount: 6), now: first)
        ledger.resolve(.shortcutOffer, id, as: .declined(atPasteCount: 12), now: later)
        #expect(ledger.isBlocked(.shortcutOffer, id, pastes: 1000, now: later.addingTimeInterval(365 * 86_400)))
    }

    @Test("a decline of one kind does not block another kind for the clip")
    func whenOneKindDeclined_thenOtherKindsStayOpen() {
        var ledger = SuggestionLedger(serialized: "")
        let id = UUID()
        ledger.resolve(.shortcutOffer, id, as: .declined(atPasteCount: 6), now: .now)
        #expect(!ledger.isBlocked(.snippet, id, pastes: 8, now: .now))
    }

    @Test("accepted, acknowledged and kept outcomes block the kind")
    func whenResolvedOtherwise_thenBlocked() {
        var ledger = SuggestionLedger(serialized: "")
        let id = UUID()
        ledger.resolve(.shortcutOffer, id, as: .accepted, now: .now)
        #expect(ledger.isBlocked(.shortcutOffer, id, pastes: 50, now: .now))
    }

    @Test("when a kind is ignored for the limit, it counts as one decline and other kinds stay open")
    func whenIgnoredToLimit_thenOnlyThatKindIsDeclined() {
        var ledger = SuggestionLedger(serialized: "")
        let id = UUID()
        let now = Date(timeIntervalSince1970: 1_000_000)
        for _ in 0..<ShelfSuggestionPolicy.Thresholds.ignoredShowsBeforeMute {
            #expect(!ledger.isBlocked(.shortcutOffer, id, pastes: 6, now: now))
            ledger.noteShown(.shortcutOffer, id, pastes: 6, now: now)
        }
        #expect(ledger.isBlocked(.shortcutOffer, id, pastes: 6, now: now))
        #expect(!ledger.isBlocked(.snippet, id, pastes: 8, now: now))
        #expect(!ledger.isBlocked(.shortcutOffer, id, pastes: 12, now: now.addingTimeInterval(30 * 86_400)))
    }

    @Test("a decline survives a round trip and an old declined line still parses")
    func whenSerialized_thenDeclineDateAndCountSurvive() {
        var ledger = SuggestionLedger(serialized: "")
        let id = UUID()
        let on = Date(timeIntervalSince1970: 1_000_000)
        ledger.resolve(.snippet, id, as: .declined(atPasteCount: 8), now: on)
        let reloaded = SuggestionLedger(serialized: ledger.serialized)
        #expect(reloaded.isBlocked(.snippet, id, pastes: 16, now: on.addingTimeInterval(29 * 86_400)))
        #expect(!reloaded.isBlocked(.snippet, id, pastes: 16, now: on.addingTimeInterval(30 * 86_400)))

        let legacy = SuggestionLedger(serialized: "snippet|\(id.uuidString)|1|declined|8")
        #expect(legacy.isBlocked(.snippet, id, pastes: 8, now: on))
        #expect(!legacy.isBlocked(.snippet, id, pastes: 16, now: .now))
    }

    @Test("pruning drops entries for clips that no longer exist")
    func whenPruned_thenOnlyExistingClipsRemain() {
        var ledger = SuggestionLedger(serialized: "")
        let keep = UUID()
        let gone = UUID()
        ledger.noteShown(.snippet, keep, pastes: 8, now: .now)
        ledger.noteShown(.snippet, gone, pastes: 8, now: .now)
        ledger.prune(existingClipIDs: [keep])
        #expect(ledger.shows(.snippet, keep) == 1)
        #expect(ledger.shows(.snippet, gone) == 0)
    }
}
