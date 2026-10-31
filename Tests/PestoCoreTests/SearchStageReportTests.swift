// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import XCTest
@testable import PestoCore

/// Reports where one search keystroke goes over 5,000 clips, so an optimised build (`swift test -c release`) can be
/// compared with the hosted Debug test in `LargeHistoryPerformanceTests`. Asserts nothing: the budget is enforced
/// there.
final class SearchStageReportTests: XCTestCase {
    private func medianMilliseconds(runs: Int = 7, _ body: () -> Void) -> Double {
        let clock = ContinuousClock()
        var samples: [Double] = []
        for _ in 0..<runs {
            let elapsed = clock.measure(body)
            samples.append(Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000)
        }
        return samples.sorted()[runs / 2]
    }

    private func makeShelfItems(count: Int) throws -> [ClipboardItem] {
        let container = try ModelContainerSetup.makeInMemory()
        let context = ModelContext(container)
        let encryption = BlobEncryption()
        for index in 0..<count {
            let text = "Clip number \(index): the quick brown fox jumps over the lazy dog, again and again."
            let item = ClipboardItem(
                type: .text, previewText: "", contentHash: "hash-\(index)", byteSize: text.utf8.count,
                deviceID: "perf", sequenceNumber: Int64(index)
            )
            let envelope = try encryption.encrypt(Data(text.utf8))
            item.previewCiphertext = envelope.ciphertext
            item.previewNonce = envelope.nonce
            context.insert(item)
        }
        try context.save()
        let items = try context.fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(
            \.timestamp, order: .reverse
        )]))
        for (index, item) in items.enumerated() where index % 25 == 0 {
            item.updateMetadata {
                $0.customTitle = "Title \(index)"
                $0.tags = ["tag\(index)"]
            }
        }
        return items
    }

    /// What the shelf did for a typed query before the history index (ADR 0007), line for line, kept to compare with.
    private func shelfFilter(_ items: [ClipboardItem], query: String) -> [ClipboardItem] {
        let foldedQuery = SearchMatching.fold(query)
        return items.filter { item in
            SearchMatching.matches(foldedText: item.searchableGridPreview, foldedQuery: foldedQuery)
                || (item.customTitle.map { SearchMatching.matches($0, query: query) } == true)
                || (item.userNote.map { SearchMatching.matches($0, query: query) } == true)
                || item.tags.contains { SearchMatching.matches($0, query: query) }
        }
    }

    func test_searchKeystroke_stageSplit_isReported() throws {
        let items = try makeShelfItems(count: 5000)
        _ = shelfFilter(items, query: "warm-up")
        let folded = SearchMatching.fold("clue")
        let plain = items.map(\.searchableGridPreview)

        let columns = medianMilliseconds { for item in items {
            _ = item.previewCiphertext
            _ = item.previewNonce
        } }
        let identity = medianMilliseconds { for item in items {
            _ = item.id
            _ = item.sensitivityMaskedPreview
        } }
        let cached = medianMilliseconds { for item in items {
            _ = item.searchableGridPreview
        } }
        let contains = medianMilliseconds { _ = plain.filter { $0.contains(folded) } }
        let metadata = medianMilliseconds { for item in items {
            _ = item.customTitle
            _ = item.userNote
            _ = item.tags
        } }
        let legacy = medianMilliseconds { for item in items {
            _ = item.legacyMetadata
        } }
        let previewOnly = medianMilliseconds {
            _ = items.filter { SearchMatching.matches(foldedText: $0.searchableGridPreview, foldedQuery: folded) }
        }
        let shelf = medianMilliseconds { _ = shelfFilter(items, query: "clue") }
        let buildStart = ContinuousClock.now
        let index = HistoryIndex(items: items)
        let build = Double((ContinuousClock.now - buildStart).components.attoseconds) / 1e15
        let indexed = medianMilliseconds { _ = index.matching(HistoryCriteria(query: "clue")) }
        let indexedNarrow = medianMilliseconds { _ = index.matching(HistoryCriteria(query: "clip number 499")) }

        let report = """
        search stages over 5,000 items, median of 7 (ms): \
        previewCiphertext+nonce columns \(columns), id+maskedPreview columns \(identity), \
        searchableGridPreview cache hit \(cached), contains over prebuilt strings \(contains), \
        customTitle+userNote+tags \(metadata), legacyMetadata alone \(legacy), \
        preview-only filter (the budget test) \(previewOnly), full shelf filter \(shelf), \
        HistoryIndex build \(build), HistoryIndex.matching \(indexed) / narrow \(indexedNarrow)
        """
        FileHandle.standardError.write(Data((report + "\n").utf8))
        add(XCTAttachment(string: report))
    }
}
