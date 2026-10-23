// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("What an import tells the person")
struct ImportReportTests {
    private let now = Date(timeIntervalSince1970: 100 * 86_400)

    private func record(daysAgo: Double, pinboard: String? = nil) -> PasteImportRecord {
        PasteImportRecord(
            pinboard: pinboard, title: nil, timestamp: now.addingTimeInterval(-daysAgo * 86_400),
            sourceBundleID: nil, representations: []
        )
    }

    private func report(
        _ records: [PasteImportRecord], imported: Int, skipped: Int = 0, librarySkipped: Int = 0, keepDays: Int = 30
    )
    -> ImportReport {
        ImportReport(
            summary: .init(imported: imported, skipped: skipped), librarySkipped: librarySkipped, records: records,
            retention: RetentionPolicy(maxAge: Double(keepDays) * 86_400, maxItemCount: 5000, maxTotalBytes: 1 << 30),
            now: now
        )
    }

    @Test("skipped clips add the migrator's and the reader's counts")
    func whenSkipped_thenBothCountsAdd() {
        let result = report([record(daysAgo: 1)], imported: 1, skipped: 2, librarySkipped: 3)

        #expect(result.imported == 1)
        #expect(result.skipped == 5)
    }

    @Test("history older than the retention setting is counted as about to expire")
    func whenOldHistory_thenExpiring() {
        let records = [record(daysAgo: 3), record(daysAgo: 45), record(daysAgo: 400)]

        #expect(report(records, imported: 3).expiring == 2)
        #expect(report(records, imported: 3, keepDays: 500).expiring == 0)
    }

    @Test("pinned clips never expire, so a pinboard's old clips are not counted")
    func whenPinned_thenNotExpiring() {
        let records = [record(daysAgo: 400, pinboard: "Commands"), record(daysAgo: 400)]

        #expect(report(records, imported: 2).expiring == 1)
    }

    @Test("it never claims more clips will expire than were imported")
    func whenFewerImported_thenCapped() {
        let records = [record(daysAgo: 100), record(daysAgo: 100), record(daysAgo: 100)]

        #expect(report(records, imported: 1).expiring == 1)
    }
}
