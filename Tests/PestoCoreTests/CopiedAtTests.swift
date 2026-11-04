// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("A clip keeps the time it was first copied")
struct CopiedAtTests {
    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        container = try ModelContainerSetup.makeInMemory()
        context = ModelContext(container)
    }

    private func clip(_ name: String, at seconds: Double) -> ClipboardItem {
        let item = ClipboardItem(
            type: .text, previewText: name, contentHash: name, byteSize: name.utf8.count, deviceID: "t",
            sequenceNumber: Int64(seconds)
        )
        item.timestamp = Date(timeIntervalSince1970: seconds)
        context.insert(item)
        return item
    }

    @Test("a clip never used reads its first copy time from its timestamp")
    func whenNeverUsed_thenCopiedAtIsTheTimestamp() {
        let item = clip("a", at: 10)
        #expect(item.copiedAt == Date(timeIntervalSince1970: 10))
        #expect(item.metadata.copiedAt == nil)
    }

    @Test("bringing a clip to the front moves its timestamp and remembers the first copy time")
    func whenBroughtToFront_thenFirstCopyTimeKept() {
        let item = clip("a", at: 10)
        item.bringToFront(at: Date(timeIntervalSince1970: 500))
        #expect(item.timestamp == Date(timeIntervalSince1970: 500))
        #expect(item.copiedAt == Date(timeIntervalSince1970: 10))
    }

    @Test("a second use does not overwrite the first copy time")
    func whenUsedTwice_thenStillTheFirstCopyTime() {
        let item = clip("a", at: 10)
        item.bringToFront(at: Date(timeIntervalSince1970: 500))
        item.bringToFront(at: Date(timeIntervalSince1970: 900))
        #expect(item.timestamp == Date(timeIntervalSince1970: 900))
        #expect(item.copiedAt == Date(timeIntervalSince1970: 10))
    }

    @Test("a paste noted by the storage service leaves the first copy time alone")
    func whenPastedThroughStorage_thenFirstCopyTimeKept() async throws {
        let service = StorageService(modelContainer: container)
        let id = try #require(await service.addSnippet("snippet {{x}}"))
        let fetched = try #require(try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
            .first { $0.id == id })
        let first = fetched.timestamp

        try await service.notePasted(id: id, at: first.addingTimeInterval(120))

        let after = try #require(try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
            .first { $0.id == id })
        #expect(after.timestamp == first.addingTimeInterval(120))
        #expect(after.copiedAt == first)
    }

    @Test("in a collection a pasted clip keeps its place, while the history still puts it in front")
    func whenPasted_thenCollectionKeepsOrderAndHistoryMovesIt() {
        let older = clip("older", at: 10)
        let newer = clip("newer", at: 20)
        #expect(CollectionOrder.sorted([older, newer]).map(\.previewText) == ["newer", "older"])

        older.bringToFront(at: Date(timeIntervalSince1970: 900))

        #expect(CollectionOrder.sorted([older, newer]).map(\.previewText) == ["newer", "older"])
        let history = [older, newer].sorted { $0.timestamp > $1.timestamp }
        #expect(history.map(\.previewText) == ["older", "newer"])
    }

    @Test("metadata sealed before the field existed still opens")
    func whenOldMetadata_thenOpensWithoutCopiedAt() throws {
        let old = Data(#"{"customTitle":"T","tags":[]}"#.utf8)
        let decoded = try JSONDecoder().decode(ItemMetadata.self, from: old)
        #expect(decoded.customTitle == "T")
        #expect(decoded.copiedAt == nil)
    }

    @Test("an earlier first-copy time from another Mac or a backup is adopted")
    func whenEarlierDateArrives_thenAdopted() {
        let item = clip("a", at: 100)
        item.adoptFirstCopy(Date(timeIntervalSince1970: 40))
        #expect(item.copiedAt == Date(timeIntervalSince1970: 40))
        #expect(item.timestamp == Date(timeIntervalSince1970: 100))
    }

    @Test("a later, missing or equal date changes nothing, and nothing is sealed for it")
    func whenNotEarlier_thenIgnored() {
        let item = clip("a", at: 100)
        item.adoptFirstCopy(Date(timeIntervalSince1970: 300))
        item.adoptFirstCopy(nil)
        item.adoptFirstCopy(Date(timeIntervalSince1970: 100))
        #expect(item.metadata.copiedAt == nil)
        #expect(item.metadataCiphertext == nil)
    }

    @Test("a clip that already remembers an earlier first copy keeps it when a later one arrives")
    func whenAlreadyEarlier_thenKept() {
        let item = clip("a", at: 10)
        item.bringToFront(at: Date(timeIntervalSince1970: 500))
        item.adoptFirstCopy(Date(timeIntervalSince1970: 200))
        #expect(item.copiedAt == Date(timeIntervalSince1970: 10))
    }
}
