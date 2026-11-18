// SPDX-License-Identifier: MIT
import Foundation
import os
import SwiftData
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("The grid lists its clips when something that decides them changes, and ranks by meaning off the main actor")
@MainActor
struct LibraryListingTests {
    private func key(_ store: HistoryStore, query: String = "") -> LibraryListing.Key {
        LibraryListing.Key(
            revision: store.revision, query: query, filter: LibraryFilter(), isSearching: false, orderVersion: 0,
            textEdits: 0, byMeaning: [], hidesSensitive: false, smartRule: nil
        )
    }

    private func vector(_ values: [Float]) -> Data {
        values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    @Test("the key changes with the history, the query, the filter, the order and edits, and with nothing else")
    func whenSomethingDecidesTheList_thenTheKeyChanges() async throws {
        let library = try await MobileTestLibrary()
        let base = key(library.store)
        #expect(key(library.store) == base)

        try await library.add("first")
        #expect(key(library.store) != base)

        var other = base
        other.query = "x"
        #expect(other != base)
        other = base
        other.filter.scope = .pinned
        #expect(other != base)
        other = base
        other.orderVersion = 1
        #expect(other != base)
        other = base
        other.textEdits = 1
        #expect(other != base)
    }

    @Test("listing newest first, a clip a copy moved to the front keeps its drawn place")
    func whenListedAgain_thenTheOrderHolds() async throws {
        let library = try await MobileTestLibrary()
        let first = try await library.add("first")
        let second = try await library.add("second")
        let order = GridOrder()

        let one = LibraryListing.list(key(library.store), in: library.store, order: order, smartRule: nil)
        #expect(one.ids == [second.id, first.id])

        first.bringToFront(at: .now.addingTimeInterval(60))
        try first.modelContext?.save()
        try await library.refreshed()
        let two = LibraryListing.list(key(library.store), in: library.store, order: order, smartRule: nil)
        #expect(two.ids == one.ids)
    }

    @Test("ranking by meaning reads every vector on a context of its own and returns the near clips, nearest first")
    func whenRanked_thenOnlyNearClipsInOrder() async throws {
        let library = try await MobileTestLibrary()
        let near = try await library.add("near clip")
        let nearer = try await library.add("nearer clip")
        let far = try await library.add("far clip")
        for (item, values) in [(near, [Float(1), 0.5]), (nearer, [1, 0.1]), (far, [0, 1])] {
            item.embeddingData = vector(values)
        }
        try #require(near.modelContext).save()
        let container = try #require(library.state.historyContainer)

        let ids = await SemanticRanking.rank(queryEmbedding: vector([1, 0]), container: container)

        #expect(ids == [nearer.id, near.id])
    }

    @Test("the same query over the same history is ranked once")
    func whenTheQueryRepeats_thenTheRankingIsRemembered() async throws {
        let library = try await MobileTestLibrary()
        let clip = try await library.add("remembered clip")
        clip.embeddingData = vector([1, 0])
        try #require(clip.modelContext).save()
        let container = try #require(library.state.historyContainer)
        let ranking = SemanticRanking()
        let query = vector([1, 0])
        let embed: @Sendable (String) async -> Data? = { _ in query }

        let first = await ranking.matches(for: "a long query", revision: 1, container: container, embed: embed)
        let again = await ranking.matches(for: "a long query", revision: 1, container: container, embed: embed)
        #expect(first == [clip.id] && again == first)
        #expect(ranking.rankCount == 1)

        _ = await ranking.matches(for: "a long query", revision: 2, container: container, embed: embed)
        #expect(ranking.rankCount == 2)
    }

    @Test("listing 5,000 clips: what one list costs, which a focus move or a minute tick no longer pays")
    func whenFiveThousandClips_thenOneListIsMeasured() throws {
        let container = try ModelContainerSetup.makeInMemory()
        let context = container.mainContext
        for number in 0..<5000 {
            context.insert(ClipboardItem(
                type: .text, previewText: "", contentHash: "hash-\(number)", byteSize: 10, deviceID: "perf",
                sequenceNumber: Int64(number)
            ))
        }
        try context.save()
        let store = HistoryStore(container: container)
        store.setVisible(true)
        store.refresh()
        #expect(store.items.count == 5000)
        let order = GridOrder()
        let clock = ContinuousClock()
        _ = LibraryListing.list(key(store), in: store, order: order, smartRule: nil)

        var samples: [Double] = []
        for _ in 0..<20 {
            let start = clock.now
            let listed = LibraryListing.list(key(store), in: store, order: order, smartRule: nil)
            samples.append(Double((clock.now - start).components.attoseconds) / 1e15)
            #expect(listed.ids.count == 5000)
        }
        let median = samples.sorted()[samples.count / 2]
        Logger(subsystem: "net.copypesto.pesto.tests", category: "ListingMeasure").notice(
            "one grid listing over 5,000 clips: median \(median, privacy: .public) ms"
        )
        #expect(median < 100)
    }
}
