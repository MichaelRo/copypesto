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

    @Test("Paste's pinboards are the pinned clips and its history is the rest, with its pinboard summary")
    func whenFromPaste_thenPinboardsArePinned() {
        let library = PasteLibrary(
            pinboards: [
                .init(name: "Commands", records: [record(daysAgo: 1, pinboard: "Commands")]),
                .init(
                    name: "Prompts",
                    records: [record(daysAgo: 2, pinboard: "Prompts"), record(daysAgo: 3, pinboard: "Prompts")]
                )
            ],
            history: [record(daysAgo: 4), record(daysAgo: 400)]
        )

        let preview = ImportPreview(paste: library)

        #expect(preview.appName == "Paste")
        #expect(preview.pinnedCount == 3)
        #expect(preview.historyCount == 2)
        #expect(preview.pinSummary == "Commands (1), Prompts (2)")
        #expect(preview.records(includingHistory: false).count == 3)
        #expect(preview.records(includingHistory: true).count == 5)
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
