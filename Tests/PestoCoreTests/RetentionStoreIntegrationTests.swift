// SPDX-License-Identifier: MIT
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

@Suite("Retention against a real store")
struct RetentionStoreIntegrationTests {
    private func makeItem(
        pinned: Bool,
        expiresAt: Date? = nil,
        sequence: Int64,
        withBlob: Bool = false
    )
    -> ClipboardItem {
        let item = ClipboardItem(
            type: .text,
            previewText: "item \(sequence)",
            contentHash: "hash-\(sequence)",
            byteSize: 10,
            deviceID: "test",
            sequenceNumber: sequence,
            isPinned: pinned
        )
        item.expiresAt = expiresAt
        if withBlob {
            item.blob = ClipboardBlob(
                encryptedData: Data(repeating: 1, count: 32),
                nonceData: Data(repeating: 2, count: 12),
                mimeType: "public.utf8-plain-text"
            )
        }
        return item
    }

    @Test("an expired pinned item is never reported as expired")
    func whenPinnedItemPastTTL_thenNotExpired() async throws {
        let container = try ModelContainerSetup.makeInMemory()
        let context = ModelContext(container)
        let pinned = makeItem(pinned: true, expiresAt: .now - 60, sequence: 1)
        let loose = makeItem(pinned: false, expiresAt: .now - 60, sequence: 2)
        context.insert(pinned)
        context.insert(loose)
        try context.save()

        let expired = try await StorageService(modelContainer: container).retentionSnapshot(expiringBefore: .now)
            .expired

        #expect(expired == [loose.id])
    }

    @Test("deleting an item removes its blob row too")
    func whenItemDeleted_thenBlobCascades() async throws {
        let container = try ModelContainerSetup.makeInMemory()
        let context = ModelContext(container)
        let item = makeItem(pinned: false, sequence: 1, withBlob: true)
        context.insert(item)
        try context.save()

        try await StorageRetentionStore(service: StorageService(modelContainer: container))
            .deleteItems(ids: [item.id])

        let remaining = try ModelContext(container).fetchCount(FetchDescriptor<ClipboardBlob>())
        #expect(remaining == 0)
    }

    @Test("a sweep keeps pinned items through age, count and TTL")
    func whenSweeping_thenPinnedItemsSurvive() async throws {
        let container = try ModelContainerSetup.makeInMemory()
        let context = ModelContext(container)
        let old = Date.now - 90 * 86_400
        let pinned = makeItem(pinned: true, expiresAt: .now - 60, sequence: 1)
        pinned.timestamp = old
        let loose = makeItem(pinned: false, sequence: 2)
        loose.timestamp = old
        context.insert(pinned)
        context.insert(loose)
        try context.save()
        let pruner = RetentionPruner(
            store: StorageRetentionStore(service: StorageService(modelContainer: container)),
            policyProvider: { RetentionPolicy(maxAge: 30 * 86_400, maxItemCount: 1, maxTotalBytes: 1_000_000) }
        )

        try await pruner.sweep()

        let left = try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
        #expect(left.map(\.id) == [pinned.id])
    }

    @Test(
        "a sweep that deletes an expired item clears its last-item file and leaves no tombstone"
    )
    func whenSweepDeletesExpiredItem_thenNoPlaintextLeftBehind() async throws {
        let container = try ModelContainerSetup.makeInMemory()
        let context = ModelContext(container)
        let expired = makeItem(pinned: false, expiresAt: .now - 60, sequence: 1, withBlob: true)
        context.insert(expired)
        try context.save()
        let spy = SpyLastItemStore()
        let service = StorageService(modelContainer: container, environment: .testing { $0.lastItemStore = spy })

        try await RetentionPruner(policy: .default, store: StorageRetentionStore(service: service)).sweep()

        #expect(spy.events.contains("clear \(expired.id.uuidString)"))
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<DeletedItemTombstone>()) == 0)
    }
}
