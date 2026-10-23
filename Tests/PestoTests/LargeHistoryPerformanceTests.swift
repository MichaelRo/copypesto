// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import SwiftData
import XCTest
@testable import Pesto

/// Budget: filtering a 5,000-item history while typing must stay under 16 ms per keystroke (one frame).
final class LargeHistoryPerformanceTests: XCTestCase {
    private func makeContext(count: Int) throws -> ModelContext {
        let container = try ModelContainerSetup.makeInMemory().synced
        let context = ModelContext(container)
        let encryption = BlobEncryption()
        for index in 0..<count {
            let text = "Clip number \(index): the quick brown fox jumps over the lazy dog, again and again."
            let item = ClipboardItem(
                type: .text,
                previewText: "",
                contentHash: "hash-\(index)",
                byteSize: text.utf8.count,
                deviceID: "perf",
                sequenceNumber: Int64(index)
            )
            let envelope = try encryption.encrypt(Data(text.utf8))
            item.previewCiphertext = envelope.ciphertext
            item.previewNonce = envelope.nonce
            context.insert(item)
        }
        try context.save()
        return context
    }

    /// The shelf filters rows on the history index (`HistoryIndex`), not the clips: a keystroke reads no SwiftData
    /// property. Before the index the same keystroke took 79 ms over 5,000 clips (19 ms for the preview alone).
    @MainActor
    func test_searchKeystroke_over5000Items_underAQuarterOfAFrame() throws {
        let context = try makeContext(count: 5000)
        let items = try context.fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(
            \.timestamp,
            order: .reverse
        )]))
        for (position, item) in items.enumerated() where position % 25 == 0 {
            item.updateMetadata {
                $0.customTitle = "Title \(position)"
                $0.tags = ["tag\(position)"]
            }
        }
        XCTAssertEqual(items.count, 5000)
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let clock = ContinuousClock()
        let start = clock.now
        let index = HistoryIndex(items: items)
        let buildMilliseconds = Double((clock.now - start).components.attoseconds) / 1e15
        add(
            XCTAttachment(string: "index build over 5,000 clips: \(buildMilliseconds) ms (once per first show, sliced)")
        )

        func keystroke(_ query: String) -> [ClipboardItem] {
            let matched = index.matching(HistoryCriteria(searchActive: true, query: query))
            // The shelf slices what is visible; materializing all 5,000 items benchmarks dictionary lookup instead of
            // search.
            return matched.prefix(100).compactMap { byID[$0] }
        }
        _ = keystroke("warm-up")
        var samples: [Double] = []
        for query in ["c", "cl", "cli", "clip", "clip number 4", "clip number 49", "title 25", "@tag50"] {
            let begin = clock.now
            let found = keystroke(query)
            samples.append(Double((clock.now - begin).components.attoseconds) / 1e15)
            XCTAssertFalse(found.isEmpty, "'\(query)' found nothing")
        }
        let slowest = samples.max() ?? 0
        PerfReport.emit("search keystroke over 5,000 clips: slowest \(slowest) ms of \(samples)")
        if !RunEnvironment.isCI {
            XCTAssertLessThan(slowest, 4, "a keystroke over 5,000 clips must leave the frame to SwiftUI")
        }
    }
}
