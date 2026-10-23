// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("One shared history for the shelf and the pinned window", .serialized)
@MainActor
struct HistoryStoreTests {
    private let container: ModelContainer
    private let service: StorageService

    init() async throws {
        container = try ModelContainerSetup.makeInMemory().synced
        service = StorageService(modelContainer: container)
    }

    private func ingest(_ text: String, at seconds: Double) async throws {
        try await service.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
            timestamp: Date(timeIntervalSince1970: seconds),
            contentHash: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        ))
    }

    @Test("a save that says nothing, from another container, does not make this store read its history again")
    func whenAnotherContainerSaves_thenTheStoreIgnoresIt() async throws {
        try await ingest("mine", at: 1000)
        let store = HistoryStore(container: container)
        store.setVisible(true)
        let fetches = store.fetchCount
        let elsewhere = try ModelContext(ModelContainerSetup.makeInMemory().synced)

        NotificationCenter.default.post(name: ModelContext.didSave, object: elsewhere)
        try await Task.sleep(for: .milliseconds(250))

        #expect(store.fetchCount == fetches, "a save elsewhere in the process made this store read its history")
    }

    @Test("a save that says nothing, from this container, still makes the store read its history again")
    func whenItsOwnContainerSavesWithoutDetail_thenTheStoreRefetches() async throws {
        try await ingest("mine", at: 1000)
        let store = HistoryStore(container: container)
        store.setVisible(true)
        let fetches = store.fetchCount

        NotificationCenter.default.post(name: ModelContext.didSave, object: ModelContext(container))
        try await store.waitForRefresh()

        #expect(store.fetchCount == fetches + 1)
    }

    @Test("a refresh still waiting out its debounce is dropped when the surfaces hide")
    func whenHiddenBeforeTheDebounce_thenNothingIsFetched() async throws {
        let store = HistoryStore(container: container)
        store.setVisible(true)
        let before = store.fetchCount

        try await ingest("late", at: 3000)
        await Task.yield()
        store.setVisible(false)
        try await Task.sleep(for: .milliseconds(250))

        #expect(store.fetchCount == before)
    }

    @Test("showing a surface loads the history, newest first")
    func whenShown_thenItemsLoad() async throws {
        try await ingest("old", at: 1000)
        try await ingest("new", at: 2000)
        let store = HistoryStore(container: container)

        store.setVisible(true)

        #expect(store.items.map(\.displayPreviewText) == ["new", "old"])
    }

    @Test("while a surface is visible a copy appears, and a delete disappears, without anyone asking")
    func whenVisible_thenSavesAreFollowed() async throws {
        try await ingest("first", at: 1000)
        let store = HistoryStore(container: container)
        store.setVisible(true)

        try await ingest("second", at: 2000)
        try await store.waitForRefresh()
        #expect(store.items.count == 2)

        _ = try await service.deleteItems(ids: [store.items[0].id], reason: .user)
        try await store.waitForRefresh()
        #expect(store.items.map(\.displayPreviewText) == ["first"])
    }

    @Test("while hidden a copy is followed without a fetch, so the next show has it ready")
    func whenHidden_thenCopiesAreFollowedWithoutAFetch() async throws {
        try await ingest("first", at: 1000)
        let store = HistoryStore(container: container)
        store.setVisible(true)
        store.setVisible(false)
        let fetchesWhileShown = store.fetchCount

        try await ingest("second", at: 2000)
        try await Task.sleep(for: .milliseconds(250))
        #expect(store.fetchCount == fetchesWhileShown, "a hidden store fetched")
        #expect(store.items.count == 2)

        store.setVisible(true)
        #expect(store.fetchCount == fetchesWhileShown, "showing it read the whole history again")
        #expect(store.items.map(\.displayPreviewText) == ["second", "first"])
    }

    @Test("a store that was never shown loads on prefetch, and then follows saves")
    func whenPrefetched_thenLoadedBeforeTheFirstShow() async throws {
        try await ingest("first", at: 1000)
        let store = HistoryStore(container: container)
        #expect(store.items.isEmpty)

        store.prefetch()
        #expect(store.items.count == 1)
        let fetches = store.fetchCount
        store.prefetch()
        #expect(store.fetchCount == fetches, "a second prefetch read the history again")

        store.setVisible(true)
        #expect(store.fetchCount == fetches, "the first show read it again")
    }

    @Test("under memory pressure the store lets go of the history, and the next show loads it again")
    func whenTrimmed_thenTheNextShowReloads() async throws {
        try await ingest("only", at: 1000)
        let store = HistoryStore(container: container)
        store.setVisible(true)
        store.setVisible(false)
        let fetches = store.fetchCount

        store.trim()
        #expect(store.items.isEmpty)
        #expect(store.hasSearchText == false)

        store.setVisible(true)
        #expect(store.fetchCount == fetches + 1)
        #expect(store.items.count == 1)
    }

    @Test("showing again with nothing saved in between does not fetch again")
    func whenNothingChanged_thenNoRefetch() async throws {
        try await ingest("only", at: 1000)
        let store = HistoryStore(container: container)
        store.setVisible(true)
        store.setVisible(false)
        let before = store.fetchCount

        store.setVisible(true)

        #expect(store.fetchCount == before)
    }

    // MARK: - Incremental updates and the search index

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(250))
    }

    @Test("a copy appears at the front without reading the whole history again")
    func whenCopied_thenInsertedWithoutRefetch() async throws {
        try await ingest("first", at: 1000)
        let store = HistoryStore(container: container)
        store.setVisible(true)
        let fetches = store.fetchCount

        try await ingest("second", at: 2000)
        try await settle()

        #expect(store.items.map(\.displayPreviewText) == ["second", "first"])
        #expect(store.fetchCount == fetches, "a copy refetched the history")
    }

    @Test("a re-copied clip moves to the front and a deleted one goes, both without a refetch")
    func whenRecopiedAndDeleted_thenFollowedWithoutRefetch() async throws {
        try await ingest("older", at: 1000)
        try await ingest("newer", at: 2000)
        let store = HistoryStore(container: container)
        store.setVisible(true)
        let fetches = store.fetchCount

        try await ingest("older", at: 3000)
        try await settle()
        #expect(store.items.map(\.displayPreviewText) == ["older", "newer"])

        _ = try await service.deleteItems(ids: [store.items[0].id], reason: .user)
        try await settle()
        #expect(store.items.map(\.displayPreviewText) == ["newer"])
        #expect(store.fetchCount == fetches)
    }

    @Test("the search index follows the history and finds what was just copied")
    func whenCopied_thenIndexFindsIt() async throws {
        try await ingest("alpha", at: 1000)
        let store = HistoryStore(container: container)
        store.setVisible(true)
        try await ingest("beta gamma", at: 2000)
        try await settle()

        let index = try #require(store.searchIndex())
        let found = index.matching(HistoryCriteria(query: "gamma"))
        #expect(found.compactMap { store.item(for: $0)?.displayPreviewText } == ["beta gamma"])
    }

    @Test("locking drops the searchable text and the next search rebuilds it")
    func whenLocked_thenTextIsDroppedAndRebuilt() async throws {
        try await ingest("secret plan", at: 1000)
        let store = HistoryStore(container: container)
        store.setVisible(true)
        #expect(try #require(store.searchIndex()).hasSearchText)

        store.dropSearchText()
        #expect(store.hasSearchText == false)

        let rebuilt = try #require(store.searchIndex())
        #expect(rebuilt.hasSearchText)
        #expect(rebuilt.matching(HistoryCriteria(query: "secret")).count == 1)
    }

    @Test("a clip edited in the shelf is searchable by its new title straight away")
    func whenTitleEdited_thenRowRefreshed() async throws {
        try await ingest("plain", at: 1000)
        let store = HistoryStore(container: container)
        store.setVisible(true)
        let item = try #require(store.items.first)

        item.customTitle = "Quarterly report"
        store.refreshRow(for: item)

        let index = try #require(store.searchIndex())
        #expect(index.matching(HistoryCriteria(query: "quarterly")) == [item.id])
    }
}
