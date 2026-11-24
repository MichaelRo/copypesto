// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("InsightsSummary")
struct InsightsSummaryTests {
    private func makeClip(
        _ preview: String,
        type: ClipboardType = .text,
        bundleID: String? = "com.apple.Notes",
        appName: String? = "Notes",
        timestamp: Date,
        pasteCount: Int = 0,
        sensitivity: SensitivityCategory? = nil,
        maskedPreview: String? = nil,
        isNSFW: Bool = false,
        analysisPending: Bool = false
    )
    -> ClipboardItem {
        let item = ClipboardItem(
            timestamp: timestamp,
            type: type,
            sourceBundleID: bundleID,
            sourceAppName: appName,
            previewText: preview,
            sensitivity: sensitivity,
            sensitivityMaskedPreview: maskedPreview,
            contentHash: UUID().uuidString,
            byteSize: preview.utf8.count,
            deviceID: "dev",
            sequenceNumber: 1
        )
        item.pasteCount = pasteCount
        item.isNSFW = isNSFW
        item.analysisPending = analysisPending
        return item
    }

    @Test("builds daily counts, type breakdown, top sources, and top pasted clips for a range")
    func whenItemsExist_thenSummaryAggregatesCountsAndRankings() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 15)))
        let oneDayAgo = try #require(calendar.date(byAdding: .day, value: -1, to: now))
        let twoDaysAgo = try #require(calendar.date(byAdding: .day, value: -2, to: now))
        let old = try #require(calendar.date(byAdding: .day, value: -10, to: now))

        let items = [
            makeClip(
                "First note",
                type: .text,
                bundleID: "com.apple.Notes",
                appName: "Notes",
                timestamp: now,
                pasteCount: 2
            ),
            makeClip(
                "Second note",
                type: .text,
                bundleID: "com.apple.Notes",
                appName: "Notes",
                timestamp: now,
                pasteCount: 5
            ),
            makeClip(
                "let x = 1",
                type: .code,
                bundleID: "com.apple.dt.Xcode",
                appName: "Xcode",
                timestamp: oneDayAgo,
                pasteCount: 9
            ),
            makeClip(
                "https://copypesto.net",
                type: .url,
                bundleID: nil,
                appName: nil,
                timestamp: twoDaysAgo,
                pasteCount: 0
            ),
            makeClip(
                "Excluded older item",
                type: .text,
                bundleID: "com.apple.Safari",
                appName: "Safari",
                timestamp: old,
                pasteCount: 99
            )
        ]

        let summary = InsightsBuilder.build(from: items, range: .sevenDays, now: now, calendar: calendar)

        #expect(summary.totalClips == 4)
        #expect(summary.dailyCounts.count == 7)
        #expect(summary.dailyCounts.last?.count == 2)
        #expect(summary.typeCounts.first?.kind == .text)
        #expect(summary.typeCounts.first?.count == 2)
        #expect(summary.topSources.first?.name == "Notes")
        #expect(summary.topSources.first?.count == 2)
        #expect(summary.topPasted.map(\.preview) == ["let x = 1", "Second note", "First note"])
        #expect(summary.topPasted.map(\.count) == [9, 5, 2])
    }

    @Test("never leaks secret, NSFW, pending, or concealed plaintext into topPasted")
    func whenItemsAreSensitiveOrConcealed_thenPlaintextNeverAppearsInTopPasted() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cardSecret = "4111-SECRET-CARD-2222"
        let keySecret = "sk-live-RAWKEY999"
        let nsfwSecret = "private-nsfw-body"
        let pendingSecret = "pending-analysis-body"
        let concealedSecret = "hand-hidden-body"

        let handHidden = makeClip(concealedSecret, timestamp: now, pasteCount: 15)
        let items = [
            makeClip(cardSecret, timestamp: now, pasteCount: 20, sensitivity: .creditCard, maskedPreview: nil),
            makeClip(keySecret, timestamp: now, pasteCount: 18, sensitivity: .apiKey, maskedPreview: "sk-••••999"),
            makeClip(nsfwSecret, timestamp: now, pasteCount: 16, isNSFW: true),
            makeClip(pendingSecret, timestamp: now, pasteCount: 14, analysisPending: true),
            handHidden,
            makeClip("Safe pasted note", timestamp: now, pasteCount: 3)
        ]

        let summary = InsightsBuilder.build(
            from: items,
            range: .sevenDays,
            now: now,
            isConcealed: { $0.id == handHidden.id }
        )

        let previews = summary.topPasted.map(\.preview).joined(separator: "\n")
        #expect(!previews.contains(cardSecret))
        #expect(!previews.contains(keySecret))
        #expect(!previews.contains(nsfwSecret))
        #expect(!previews.contains(pendingSecret))
        #expect(!previews.contains(concealedSecret))
        #expect(summary.topPasted.contains { $0.preview == "Safe pasted note" && $0.count == 3 })
    }
}
