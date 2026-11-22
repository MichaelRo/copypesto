// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("iOS LibraryListing stays fast over 5,000 clips")
@MainActor
struct LibraryListingPerformanceTests {
    @Test("listing all and searched views over 5,000 clips completes under 150 ms median")
    func whenListing5000Clips_thenStaysUnderBudget() async throws {
        let library = try await MobileTestLibrary()
        let context = try #require(library.state.historyContainer).mainContext
        let now = Date.now
        for offset in 0..<5000 {
            let item = ClipboardItem(
                type: offset.isMultiple(of: 7) ? .url : .text,
                previewText: "Clip item number \(offset) with searchable keywords",
                contentHash: "hash-\(offset)",
                byteSize: 128,
                deviceID: "test-device",
                sequenceNumber: Int64(offset),
                isPinned: offset.isMultiple(of: 20)
            )
            item.timestamp = now.addingTimeInterval(TimeInterval(-offset))
            context.insert(item)
        }
        try context.save()
        try await library.refreshed()

        let allKey = LibraryListing.Key(
            revision: library.store.revision,
            query: "",
            filter: LibraryFilter(),
            isSearching: false,
            orderVersion: 0,
            textEdits: 0,
            byMeaning: [],
            hidesSensitive: true,
            smartRule: nil
        )
        let searchKey = LibraryListing.Key(
            revision: library.store.revision,
            query: "searchable",
            filter: LibraryFilter(),
            isSearching: true,
            orderVersion: 0,
            textEdits: 0,
            byMeaning: [],
            hidesSensitive: true,
            smartRule: nil
        )

        let clock = ContinuousClock()
        var samples: [Double] = []
        for _ in 0..<5 {
            let order = GridOrder()
            let duration = clock.measure {
                let all = LibraryListing.list(allKey, in: library.store, order: order, smartRule: nil)
                let searched = LibraryListing.list(searchKey, in: library.store, order: order, smartRule: nil)
                #expect(all.ids.count == 5000)
                #expect(searched.ids.count == 5000)
            }
            let ms = Double(duration.components.seconds) * 1000
                + Double(duration.components.attoseconds) / 1_000_000_000_000_000
            samples.append(ms)
        }
        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        #expect(median < 150, "LibraryListing median \(median) ms exceeded 150 ms")
    }
}
