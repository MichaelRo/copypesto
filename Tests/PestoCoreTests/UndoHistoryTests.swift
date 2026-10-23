// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Undo history keeps the order, the budget and the wipe")
struct UndoHistoryTests {
    private func entry(_ name: String, bytes: Int = 0) -> UndoEntry {
        UndoEntry(.collectionDeleted(PinboardSnapshot(
            name: name, smartPredicateData: bytes > 0 ? Data(count: bytes) : nil
        )))
    }

    @Test("the newest action is undone first, then waits to be redone")
    func whenUndone_thenRedoable() throws {
        let history = UndoHistory()
        history.record(entry("first"))
        history.record(entry("second"))
        #expect(history.undoLabel == .deleteCollection("second"))

        let taken = try #require(history.takeUndo())
        history.pushRedo(taken)

        #expect(history.undoLabel == .deleteCollection("first"))
        #expect(history.redoLabel == .deleteCollection("second"))
    }

    @Test("a new action ends the redo")
    func whenRecorded_thenRedoIsForgotten() throws {
        let history = UndoHistory()
        history.record(entry("a"))
        try history.pushRedo(#require(history.takeUndo()))
        #expect(history.redoLabel != nil)

        history.record(entry("b"))

        #expect(history.redoLabel == nil)
    }

    @Test("the oldest entry goes first when there are too many")
    func whenOverTheEntryLimit_thenTheOldestGoes() {
        let history = UndoHistory(maxEntries: 3)
        for name in ["a", "b", "c", "d"] {
            history.record(entry(name))
        }

        #expect(history.entryCount == 3)
        _ = history.takeUndo()
        _ = history.takeUndo()
        #expect(history.undoLabel == .deleteCollection("b"))
    }

    @Test("the oldest entry goes first when the held bytes pass the budget")
    func whenOverTheByteBudget_thenTheOldestGoes() {
        let history = UndoHistory(maxHeldBytes: 10_000)
        history.record(entry("a", bytes: 4000))
        history.record(entry("b", bytes: 4000))
        history.record(entry("c", bytes: 4000))

        #expect(history.heldBytes <= 10_000)
        #expect(history.entryCount == 2)
        #expect(history.undoLabel == .deleteCollection("c"))
    }

    @Test("an entry bigger than the whole budget is not kept, and keeps nothing else out")
    func whenTooBig_thenNotRecorded() {
        let history = UndoHistory(maxHeldBytes: 10_000)
        history.record(entry("small"))

        #expect(history.record(entry("huge", bytes: 20_000)) == false)

        #expect(history.undoLabel == .deleteCollection("small"))
    }

    @Test("clear empties both stacks")
    func whenCleared_thenNothingIsLeft() throws {
        let history = UndoHistory()
        history.record(entry("a"))
        history.record(entry("b"))
        try history.pushRedo(#require(history.takeUndo()))

        history.clear()

        #expect(history.undoLabel == nil && history.redoLabel == nil)
        #expect(history.entryCount == 0 && history.heldBytes == 0)
    }

    @Test("a clip is held unless it is large, expiring, a credential or still being analyzed")
    func whenJudged_thenPolicyDecides() {
        func holds(
            _ bytes: Int = 100, expires: Date? = nil, sensitivity: String? = nil, pending: Bool = false
        )
        -> Bool {
            UndoPolicy.canHold(
                byteSize: bytes,
                expiresAt: expires,
                sensitivityRaw: sensitivity,
                analysisPending: pending
            )
        }
        #expect(holds())
        #expect(holds(sensitivity: "api_key"))
        #expect(!holds(UndoPolicy.maxClipBytes + 1))
        #expect(!holds(expires: .now.addingTimeInterval(60)))
        #expect(!holds(sensitivity: "credential"))
        #expect(!holds(pending: true))
        #expect(UndoPolicy.canHold(clipCount: 200))
        #expect(!UndoPolicy.canHold(clipCount: 201))
        #expect(!UndoPolicy.canHold(clipCount: 0))
    }
}
