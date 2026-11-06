// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Which clips of a big Paste library an import takes")
struct PasteImportPlanTests {
    private let now = Date(timeIntervalSince1970: 1000 * 86_400)
    private let forever = RetentionPolicy(maxAge: .infinity, maxItemCount: 1_000_000, maxTotalBytes: .max)

    private func row(
        _ key: Int64, bytes: Int? = 10, daysAgo: Double = 1, board: String? = nil, data: Int64? = nil
    )
    -> PasteImportPlanner.Row {
        .init(
            snippetKey: key, dataKey: bytes == nil ? nil : (data ?? key), bytes: bytes,
            timestamp: now.addingTimeInterval(-daysAgo * 86_400), pinboard: board
        )
    }

    private func planner(clips: Int = 5, bytes: Int = 1000) -> PasteImportPlanner {
        PasteImportPlanner(cap: ImportCap(maxClips: clips, maxBytes: bytes), maxRecordBytes: 500)
    }

    @Test("a library exactly at the clip cap is taken whole, and one clip more leaves the oldest out")
    func whenAtTheClipCap_thenEdgesAreInclusive() {
        var exact = planner(clips: 3)
        for key in 1...3 {
            exact.addHistory(row(Int64(key), daysAgo: Double(key)))
        }
        let whole = exact.plan(retention: forever, now: now)
        #expect(whole.history.count == 3 && whole.leftByLimits == 0 && !whole.isLimited)

        var over = planner(clips: 3)
        for key in 1...4 {
            over.addHistory(row(Int64(key), daysAgo: Double(key)))
        }
        let plan = over.plan(retention: forever, now: now)
        #expect(plan.history.map(\.snippetKey) == [1, 2, 3])
        #expect(plan.historyLeftByCap == 1 && plan.libraryClips == 4)
    }

    @Test("a library exactly at the byte cap is taken whole, and one byte more ends the list")
    func whenAtTheByteCap_thenEdgesAreInclusive() {
        var exact = planner(clips: 10, bytes: 30)
        for key in 1...3 {
            exact.addHistory(row(Int64(key), bytes: 10, daysAgo: Double(key)))
        }
        #expect(exact.plan(retention: forever, now: now).history.count == 3)

        var over = planner(clips: 10, bytes: 30)
        for key in 1...3 {
            over.addHistory(row(Int64(key), bytes: key == 3 ? 11 : 10, daysAgo: Double(key)))
        }
        let plan = over.plan(retention: forever, now: now)
        #expect(plan.history.map(\.snippetKey) == [1, 2] && plan.historyLeftByCap == 1)
    }

    @Test("the first clip that does not fit ends the list, so a small older clip is not taken past it")
    func whenOneClipDoesNotFit_thenNothingOlderIsTaken() {
        var planner = planner(clips: 10, bytes: 25)
        planner.addHistory(row(1, bytes: 10, daysAgo: 1))
        planner.addHistory(row(2, bytes: 20, daysAgo: 2))
        planner.addHistory(row(3, bytes: 1, daysAgo: 3))

        let plan = planner.plan(retention: forever, now: now)

        #expect(plan.history.map(\.snippetKey) == [1])
        #expect(plan.historyLeftByCap == 2)
    }

    @Test("a clip over the per-clip size or with no payload takes no slot and does not end the list")
    func whenUnusable_thenSkippedWithoutAFight() {
        var planner = planner(clips: 2)
        planner.addHistory(row(1, bytes: 501))
        planner.addHistory(row(2, bytes: nil))
        planner.addHistory(row(3, bytes: 0))
        planner.addHistory(row(4))
        planner.addHistory(row(5))

        let plan = planner.plan(retention: forever, now: now)

        #expect(plan.history.map(\.snippetKey) == [4, 5])
        #expect(plan.unusable == 3 && plan.leftByLimits == 0)
    }

    @Test("pinboards are taken before history and count against the same cap")
    func whenBothFillTheCap_thenPinboardsWinInOrder() {
        var planner = planner(clips: 3)
        planner.addPinboard(row(10, daysAgo: 400, board: "Commands"))
        planner.addPinboard(row(11, daysAgo: 500, board: "Prompts"))
        for key in 1...3 {
            planner.addHistory(row(Int64(key), daysAgo: Double(key)))
        }

        let plan = planner.plan(retention: forever, now: now)

        #expect(plan.pinboards.map(\.snippetKey) == [10, 11])
        #expect(plan.history.map(\.snippetKey) == [1])
        #expect(plan.historyLeftByCap == 2)
        #expect(plan.pinSummary == "Commands (1), Prompts (1)")
    }

    @Test("pinboards that alone pass the cap are cut in board order, and no history is taken")
    func whenPinboardsExceedTheCap_thenCutInOrder() {
        var planner = planner(clips: 2)
        planner.addPinboard(row(1, board: "A"))
        planner.addPinboard(row(2, board: "A"))
        planner.addPinboard(row(3, board: "B"))
        planner.addHistory(row(4))

        let plan = planner.plan(retention: forever, now: now)

        #expect(plan.pinboards.map(\.snippetKey) == [1, 2])
        #expect(plan.pinboardsLeftByCap == 1 && plan.historyLeftByCap == 1 && plan.history.isEmpty)
    }

    @Test("a clip in two pinboards, or in a pinboard and in history, counts once")
    func whenASnippetIsInSeveralLists_thenItCountsOnce() {
        var planner = planner()
        planner.addPinboard(row(1, board: "A"))
        planner.addPinboard(row(1, board: "B"))
        planner.addHistory(row(1))
        planner.addHistory(row(2))

        let plan = planner.plan(retention: forever, now: now)

        #expect(plan.pinboards.count == 1 && plan.pinboards.first?.pinboard == "A")
        #expect(plan.history.map(\.snippetKey) == [2])
        #expect(plan.libraryClips == 2)
    }

    @Test("what retention would remove again is not imported, and the oldest of the imported go first")
    func whenRetentionIsShort_thenOnlyTheNewestSurvive() {
        var planner = planner(clips: 100)
        for key in 1...10 {
            planner.addHistory(row(Int64(key), daysAgo: Double(key)))
        }
        let policy = RetentionPolicy(maxAge: .infinity, maxItemCount: 4, maxTotalBytes: .max)

        let plan = planner.plan(retention: policy, now: now)

        #expect(plan.history.map(\.snippetKey) == [1, 2, 3, 4])
        #expect(plan.historyLeftByRetention == 6)
        #expect(plan.displacedExisting == 0)
    }

    @Test("an age limit leaves out the imported clips older than it, and what stays is a newest-first prefix")
    func whenAgeLimit_thenOlderClipsAreLeftOut() {
        var planner = planner(clips: 100)
        for key in 1...10 {
            planner.addHistory(row(Int64(key), daysAgo: Double(key)))
        }
        let policy = RetentionPolicy(maxAge: 3.5 * 86_400, maxItemCount: 1000, maxTotalBytes: .max)

        let plan = planner.plan(retention: policy, now: now)

        #expect(plan.history.map(\.snippetKey) == [1, 2, 3])
        #expect(plan.historyLeftByRetention == 7)
    }

    @Test("existing clips older than the imported ones are the ones displaced, and they are counted")
    func whenImportedAreNewer_thenOlderExistingClipsAreCounted() {
        var planner = planner(clips: 100)
        for key in 1...3 {
            planner.addHistory(row(Int64(key), daysAgo: Double(key)))
        }
        let existing = (0..<4).map { (UUID(), now.addingTimeInterval(-Double(20 + $0) * 86_400), 10) }
        let policy = RetentionPolicy(maxAge: .infinity, maxItemCount: 5, maxTotalBytes: .max)

        let plan = planner.plan(retention: policy, existing: existing, now: now)

        #expect(plan.history.count == 3 && plan.displacedExisting == 2)
    }

    @Test("every clip in the library is selected, left out by a limit, or unusable")
    func whenPlanned_thenTheNumbersAddUp() {
        var planner = planner(clips: 6, bytes: 1000)
        planner.addPinboard(row(100, board: "A"))
        planner.addPinboard(row(101, bytes: nil, board: "A"))
        for key in 1...20 {
            planner.addHistory(row(Int64(key), bytes: key == 3 ? 900 : 10, daysAgo: Double(key)))
        }
        let policy = RetentionPolicy(maxAge: .infinity, maxItemCount: 3, maxTotalBytes: .max)

        let plan = planner.plan(retention: policy, now: now)

        #expect(plan.selectedCount + plan.leftByLimits + plan.unusable == plan.libraryClips)
        #expect(plan.libraryClips == 22)
    }

    @Test("a library imported before is not counted against retention again, or imported again")
    func whenClipsAreAlreadyStored_thenTheyAreLeftOutOfTheMath() {
        var planner = planner(clips: 100)
        for key in 1...5 {
            planner.addHistory(row(Int64(key), daysAgo: Double(key)))
        }
        let existing = (1...5).map { (UUID(), now.addingTimeInterval(-Double($0) * 86_400), 10) }
        let policy = RetentionPolicy(maxAge: .infinity, maxItemCount: 5, maxTotalBytes: .max)

        let plan = planner.plan(retention: policy, existing: existing, now: now)

        #expect(plan.history.isEmpty && plan.alreadyInPesto == 5)
        #expect(plan.historyLeftByRetention == 0 && plan.displacedExisting == 0)
        #expect(plan.selectedCount + plan.leftByLimits + plan.unusable + plan.alreadyInPesto == plan.libraryClips)
        #expect(!plan.isLimited)
    }

    @Test("only the clips not stored yet are imported, and the stored ones are counted once when making room")
    func whenSomeClipsAreStored_thenOnlyTheNewOnesCompeteForRoom() {
        var planner = planner(clips: 100)
        for key in 1...6 {
            planner.addHistory(row(Int64(key), daysAgo: Double(key)))
        }
        let existing = (4...6).map { (UUID(), now.addingTimeInterval(-Double($0) * 86_400), 10) }
        let policy = RetentionPolicy(maxAge: .infinity, maxItemCount: 4, maxTotalBytes: .max)

        let plan = planner.plan(retention: policy, existing: existing, now: now)

        #expect(plan.alreadyInPesto == 3)
        #expect(plan.history.map(\.snippetKey) == [1, 2, 3])
        #expect(plan.historyLeftByRetention == 0 && plan.displacedExisting == 2)
        #expect(plan.selectedCount + plan.leftByLimits + plan.unusable + plan.alreadyInPesto == plan.libraryClips)
    }

    @Test("nothing fits when every clip is past the limits, and the summary says so")
    func whenNothingFits_thenLeadSaysNothing() {
        var planner = planner(clips: 100)
        for key in 1...3 {
            planner.addHistory(row(Int64(key), daysAgo: 100))
        }
        let policy = RetentionPolicy(maxAge: 30 * 86_400, maxItemCount: 100, maxTotalBytes: .max)

        let plan = planner.plan(retention: policy, now: now)

        #expect(plan.selectedCount == 0 && plan.isLimited)
        #expect(plan.lead(includingHistory: true) == .nothing)
    }
}
