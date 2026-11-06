// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("What an import offers before it starts")
struct ImportPreviewTests {
    private let now = Date(timeIntervalSince1970: 100 * 86_400)

    private func record(daysAgo: Double, pinboard: String? = nil) -> PasteImportRecord {
        PasteImportRecord(
            pinboard: pinboard, title: nil, timestamp: now.addingTimeInterval(-daysAgo * 86_400),
            sourceBundleID: nil, representations: []
        )
    }

    private func retention(days: Int) -> RetentionPolicy {
        RetentionPolicy(maxAge: Double(days) * 86_400, maxItemCount: 5000, maxTotalBytes: 1 << 30)
    }

    @Test("a Paste plan shows its pinboards as the pinned clips and its history as the rest, with its summary")
    func whenFromPaste_thenPinboardsArePinned() {
        func entry(_ key: Int64, _ board: String?) -> PasteImportPlan.Entry {
            .init(snippetKey: key, dataKey: key, bytes: 10, timestamp: now, pinboard: board)
        }
        let plan = PasteImportPlan(
            pinboards: [entry(1, "Commands"), entry(2, "Prompts"), entry(3, "Prompts")],
            history: [entry(4, nil), entry(5, nil)], libraryClips: 30_000, unusable: 2, pinboardsLeftByCap: 0,
            historyLeftByCap: 0, historyLeftByRetention: 29_993, displacedExisting: 0
        )

        let preview = ImportPreview(paste: plan, snapshot: nil)

        #expect(preview.appName == "Paste")
        #expect(preview.pinnedCount == 3 && preview.historyCount == 2 && preview.hasPins)
        #expect(preview.pinSummary == "Commands (1), Prompts (2)")
        #expect(preview.skipped == 2)
        #expect(plan.selectedCount + plan.leftByLimits + plan.unusable == plan.libraryClips)
        #expect(plan.lead(includingHistory: true) == .pinboardsAndNewest(2))
        #expect(plan.lead(includingHistory: false) == .pinboards)
        #expect(plan.selectedCount(includingHistory: false) == 3)
    }

    @Test("with no pinboards the summary names the newest clips, and with pinboards cut it names the first ones")
    func whenNoPinboardsOrCut_thenLeadNamesWhatIsTaken() {
        let one = PasteImportPlan.Entry(snippetKey: 1, dataKey: 1, bytes: 10, timestamp: now, pinboard: nil)
        let board = PasteImportPlan.Entry(snippetKey: 2, dataKey: 2, bytes: 10, timestamp: now, pinboard: "A")
        let newest = PasteImportPlan(
            pinboards: [], history: [one], libraryClips: 5, unusable: 0, pinboardsLeftByCap: 0, historyLeftByCap: 4,
            historyLeftByRetention: 0, displacedExisting: 0
        )
        let cut = PasteImportPlan(
            pinboards: [board], history: [], libraryClips: 5, unusable: 0, pinboardsLeftByCap: 3,
            historyLeftByCap: 1, historyLeftByRetention: 0, displacedExisting: 0
        )

        #expect(newest.lead(includingHistory: true) == .newest(1))
        #expect(cut.lead(includingHistory: true) == .firstPinboards(1))
        #expect(cut.lead(includingHistory: false) == .firstPinboards(1))
    }

    @Test("a Maccy or Alfred library is split by whether the record is in a pinboard, in its original order")
    func whenFromAnotherApp_thenSplitByPinboard() {
        let library = ClipboardAppLibrary(
            records: [
                record(daysAgo: 5), record(daysAgo: 6, pinboard: "Pinned in Maccy"), record(daysAgo: 7),
                record(daysAgo: 8, pinboard: "Pinned in Maccy")
            ],
            skipped: 4
        )

        let preview = ImportPreview(appName: "Maccy", library: library)

        #expect(preview.pinnedCount == 2)
        #expect(preview.historyCount == 2)
        #expect(preview.skipped == 4)
        #expect(preview.pinSummary == "Pinned in Maccy (2)")
        #expect(preview.records(includingHistory: true).map(\.timestamp) == [
            now.addingTimeInterval(-6 * 86_400), now.addingTimeInterval(-8 * 86_400),
            now.addingTimeInterval(-5 * 86_400), now.addingTimeInterval(-7 * 86_400)
        ])
    }

    @Test("a library with no pins has no pin summary, and its oldest clip is the oldest date")
    func whenNoPins_thenNoSummaryAndOldestIsKnown() {
        let preview = ImportPreview(
            appName: "Alfred",
            library: ClipboardAppLibrary(
                records: [record(daysAgo: 3), record(daysAgo: 90), record(daysAgo: 10)],
                skipped: 0
            )
        )

        #expect(preview.pinnedCount == 0)
        #expect(preview.pinSummary == nil)
        #expect(preview.oldest == now.addingTimeInterval(-90 * 86_400))
        #expect(!preview.hasPins)
    }

    @Test("clips the retention setting would remove are counted from history only, and only when history is imported")
    func whenRetention_thenOnlyHistoryOlderThanItExpires() {
        let preview = ImportPreview(
            appName: "Maccy",
            library: ClipboardAppLibrary(
                records: [
                    record(daysAgo: 400, pinboard: "Pinned in Maccy"),
                    record(daysAgo: 45),
                    record(daysAgo: 400),
                    record(daysAgo: 2)
                ],
                skipped: 0
            )
        )

        #expect(preview.expiring(retention: retention(days: 30), now: now, includingHistory: true) == 2)
        #expect(preview.expiring(retention: retention(days: 30), now: now, includingHistory: false) == 0)
        #expect(preview.expiring(retention: retention(days: 500), now: now, includingHistory: true) == 0)
    }

    @Test("an empty library has nothing to import")
    func whenEmpty_thenNothing() {
        let preview = ImportPreview(appName: "Alfred", library: ClipboardAppLibrary(records: [], skipped: 7))

        #expect(preview.isEmpty)
        #expect(preview.oldest == nil)
        #expect(preview.records(includingHistory: true).isEmpty)
    }
}
