// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("Tombstones", .serialized)
struct TombstoneTests {
    private let container: ModelContainer
    private let service: StorageService

    init() async throws {
        container = try ModelContainerSetup.makeInMemory()
        service = StorageService(modelContainer: container)
    }

    private func capture(text: String, timestamp: Date) -> PasteboardCapture {
        PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
            timestamp: timestamp, contentHash: "hash-\(text)"
        )
    }

    private func fetchItems() throws -> [ClipboardItem] {
        try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
    }

    @Test("only a deletion the person made leaves a tombstone")
    func deleteItems_tombstonesOnlyUserDeletes() async throws {
        try await service.ingest(capture(text: "user", timestamp: .now))
        try await service.ingest(capture(text: "aged out", timestamp: .now.addingTimeInterval(1)))
        try await service.ingest(capture(text: "cleared", timestamp: .now.addingTimeInterval(2)))
        let byText = try Dictionary(uniqueKeysWithValues: fetchItems().map { ($0.displayPreviewText, $0.id) })

        try await service.deleteItems(ids: [#require(byText["aged out"])], reason: .retention)
        try await service.deleteItems(ids: [#require(byText["cleared"])], reason: .clear)
        try await service.deleteItems(ids: [#require(byText["user"])], reason: .user)

        let tombstones = try ModelContext(container).fetch(FetchDescriptor<DeletedItemTombstone>())
        #expect(try tombstones.map(\.id) == [#require(byText["user"])])
    }

    @Test("a retention sweep also forgets tombstones older than a year")
    func deleteItems_retentionPrunesOldTombstones() async throws {
        let context = ModelContext(container)
        let old = UUID()
        let recent = UUID()
        context.insert(DeletedItemTombstone(id: old, deletedAt: Date.now.addingTimeInterval(-400 * 86_400)))
        context.insert(DeletedItemTombstone(id: recent, deletedAt: .now))
        try context.save()

        try await service.deleteItems(ids: [], reason: .retention)

        let left = try ModelContext(container).fetch(FetchDescriptor<DeletedItemTombstone>()).map(\.id)
        #expect(left == [recent])
    }
}
