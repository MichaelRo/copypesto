// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Synchronization
import Testing
@testable import PestoCore

private final class SpyLastItemStore: LastItemStoring {
    private let state = Mutex<[String]>([])
    var events: [String] {
        state.withLock { $0 }
    }

    func write(id _: UUID, preview _: String, type _: String, timestamp _: Date, sourceApp _: String?) {}
    func clear() {
        state.withLock { $0.append("clear") }
    }

    func clear(ifItemID id: UUID) {
        state.withLock { $0.append("clear \(id.uuidString)") }
    }
}

@Suite("StorageService append to latest")
struct StorageServiceAppendTests {
    private let container: ModelContainer
    private let service: StorageService
    private let lastItem = SpyLastItemStore()

    init() async throws {
        container = try ModelContainerSetup.makeInMemory()
        let spy = lastItem
        service = StorageService(modelContainer: container, environment: .testing { $0.lastItemStore = spy })
    }

    private func fetchItems() throws -> [ClipboardItem] {
        try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp)]))
    }

    private func capture(text: String, timestamp: Date) -> PasteboardCapture {
        PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text",
            payload: Data(text.utf8),
            payloadString: text,
            timestamp: timestamp,
            contentHash: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        )
    }

    @Test("appendToLatest masks an item whose combined text is sensitive and keeps it out of the last-item file")
    func appendToLatest_sensitiveCombination_isMasked() async throws {
        let t0 = Date(timeIntervalSinceReferenceDate: 6_100_000)
        await service.updateClock { t0 }
        try await service.ingest(capture(text: "my card", timestamp: t0))
        let id = try #require(fetchItems().first?.id)
        await service.updateClock { t0.addingTimeInterval(1) }
        try await service.appendToLatest(capture(text: "4111 1111 1111 1111", timestamp: t0.addingTimeInterval(1)))

        let item = try #require(fetchItems().first)
        #expect(item.sensitivity == .creditCard)
        #expect(item.sensitivityMaskedPreview != nil)
        #expect(!item.previewText.contains("4111"))
        #expect(item.previewCiphertext == nil)
        #expect(lastItem.events.contains("clear \(id.uuidString)"))
    }

    @Test("appendToLatest keeps an already sensitive item sensitive")
    func appendToLatest_alreadySensitive_staysSensitive() async throws {
        let t0 = Date(timeIntervalSinceReferenceDate: 6_200_000)
        await service.updateClock { t0 }
        try await service.ingest(capture(text: "4111 1111 1111 1111", timestamp: t0))
        await service.updateClock { t0.addingTimeInterval(1) }
        try await service.appendToLatest(capture(text: "expires next year", timestamp: t0.addingTimeInterval(1)))

        let item = try #require(fetchItems().first)
        #expect(item.sensitivity == .creditCard)
        #expect(!item.previewText.contains("4111"))
    }

    private func fullText(of item: ClipboardItem) -> String? {
        item.blob?.decryptedText()
    }

    @Test("a double press: the first press was stored as its own clip, so the second appends to the clip before it")
    func appendToLatest_afterTheFirstPressWasStored_appendsToTheClipBefore() async throws {
        let t0 = Date(timeIntervalSinceReferenceDate: 6_300_000)
        await service.updateClock { t0 }
        try await service.ingest(capture(text: "alpha", timestamp: t0))
        await service.updateClock { t0.addingTimeInterval(5) }
        try await service.ingest(capture(text: "beta", timestamp: t0.addingTimeInterval(5)))
        await service.updateClock { t0.addingTimeInterval(5.3) }
        try await service.appendToLatest(capture(text: "beta", timestamp: t0.addingTimeInterval(5.3)))

        let items = try fetchItems()
        #expect(items.count == 1, "the clip made by the first press is merged away")
        #expect(try fullText(of: #require(items.first)) == "alpha\nbeta")
    }

    @Test("a double press leaves no tombstone for the clip it merged away")
    func appendToLatest_mergedClip_leavesNoTombstone() async throws {
        let t0 = Date(timeIntervalSinceReferenceDate: 6_400_000)
        await service.updateClock { t0 }
        try await service.ingest(capture(text: "one", timestamp: t0))
        await service.updateClock { t0.addingTimeInterval(5) }
        try await service.ingest(capture(text: "two", timestamp: t0.addingTimeInterval(5)))
        await service.updateClock { t0.addingTimeInterval(5.2) }
        try await service.appendToLatest(capture(text: "two", timestamp: t0.addingTimeInterval(5.2)))

        #expect(try ModelContext(container).fetch(FetchDescriptor<DeletedItemTombstone>()).isEmpty)
    }

    @Test("a double press on text the history already held does not delete that older clip")
    func appendToLatest_firstPressWasAnOlderClip_keepsIt() async throws {
        let t0 = Date(timeIntervalSinceReferenceDate: 6_500_000)
        await service.updateClock { t0 }
        try await service.ingest(capture(text: "older", timestamp: t0))
        await service.updateClock { t0.addingTimeInterval(5) }
        try await service.ingest(capture(text: "latest", timestamp: t0.addingTimeInterval(5)))
        await service.updateClock { t0.addingTimeInterval(10) }
        try await service.ingest(capture(text: "older", timestamp: t0.addingTimeInterval(10)))
        await service.updateClock { t0.addingTimeInterval(10.3) }
        try await service.appendToLatest(capture(text: "older", timestamp: t0.addingTimeInterval(10.3)))

        let texts = try fetchItems().compactMap(fullText(of:))
        #expect(texts.contains("older"), "the clip the person re-copied is still there")
        #expect(texts.count == 2)
    }

    @Test("copying the same text twice, long after it was stored, only re-dates it")
    func appendToLatest_sameTextLongAfter_onlyRedates() async throws {
        let t0 = Date(timeIntervalSinceReferenceDate: 6_600_000)
        await service.updateClock { t0 }
        try await service.ingest(capture(text: "alpha", timestamp: t0))
        await service.updateClock { t0.addingTimeInterval(5) }
        try await service.ingest(capture(text: "beta", timestamp: t0.addingTimeInterval(5)))
        await service.updateClock { t0.addingTimeInterval(60) }
        try await service.appendToLatest(capture(text: "beta", timestamp: t0.addingTimeInterval(60)))

        #expect(try fetchItems().count == 2)
    }
}
