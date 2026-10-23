// SPDX-License-Identifier: MIT
import Foundation
import Synchronization
import Testing
@testable import PestoCore

// MARK: - Mock store

// swiftlint:disable large_tuple
private actor MockRetentionStore: RetentionStore {
    private(set) var deletedIDs: [UUID] = []
    var candidates: [(UUID, Date, Int)] = []
    var shouldThrow = false
    var expiredIDs: [UUID] = []
    private(set) var snapshotReads = 0
    private(set) var deleteCalls = 0

    func retentionSnapshot(expiringBefore _: Date) async throws -> RetentionSnapshot {
        if shouldThrow { throw TestError.intentional }
        snapshotReads += 1
        return RetentionSnapshot(candidates: candidates, expired: expiredIDs)
    }

    func deleteItems(ids: [UUID]) async throws {
        if shouldThrow { throw TestError.intentional }
        deleteCalls += 1
        deletedIDs.append(contentsOf: ids)
    }
}

// swiftlint:enable large_tuple

private enum TestError: Error {
    case intentional
}

// MARK: - Suite

@Suite("RetentionPruner sweep")
struct RetentionPrunerTests {
    private let now = Date()

    @Test("whenTheUserChangesRetention_thenTheNextSweepUsesIt")
    func whenTheUserChangesRetention_thenTheNextSweepUsesIt() async throws {
        // The pruner always used the 30-day default whatever the user chose.
        let store = MockRetentionStore()
        let fortyDaysOld = UUID()
        await store.set(candidates: [(fortyDaysOld, now.addingTimeInterval(-40 * 86_400), 100)])
        let days = Mutex(365)
        let pruner = RetentionPruner(store: store) {
            RetentionPolicy(
                maxAge: Double(days.withLock { $0 }) * 86_400,
                maxItemCount: 5000,
                maxTotalBytes: 1_000_000_000
            )
        }

        try await pruner.sweep(now: now)
        #expect(await store.deletedIDs.isEmpty, "a 40-day-old item must survive a 365-day setting")

        days.withLock { $0 = 30 }
        try await pruner.sweep(now: now)
        #expect(await store.deletedIDs == [fortyDaysOld])
    }

    @Test("whenSweep_deletesEvictedIDs")
    func whenSweep_deletesEvictedIDs() async throws {
        let store = MockRetentionStore()
        let policy = RetentionPolicy(maxAge: 60, maxItemCount: 1000, maxTotalBytes: 1_000_000_000)
        let id1 = UUID()
        let id2 = UUID()
        await store.set(candidates: [
            (id1, now.addingTimeInterval(-120), 100),
            (id2, now.addingTimeInterval(-10), 100)
        ])
        let pruner = RetentionPruner(policy: policy, store: store)
        try await pruner.sweep(now: now)

        let deleted = await store.deletedIDs
        #expect(deleted == [id1])
    }

    @Test("whenNothingToEvict_deleteIsNotCalled")
    func whenNothingToEvict_deleteIsNotCalled() async throws {
        let store = MockRetentionStore()
        let policy = RetentionPolicy(maxAge: 86_400, maxItemCount: 1000, maxTotalBytes: 1_000_000_000)
        await store.set(candidates: [
            (UUID(), now.addingTimeInterval(-100), 50)
        ])
        let pruner = RetentionPruner(policy: policy, store: store)
        try await pruner.sweep(now: now)

        let deleted = await store.deletedIDs
        #expect(deleted.isEmpty)
    }

    @Test("whenStoreThrows_sweepPropagatesError")
    func whenStoreThrows_sweepPropagatesError() async throws {
        let store = MockRetentionStore()
        await store.set(shouldThrow: true)
        let pruner = RetentionPruner(store: store)
        await #expect(throws: TestError.intentional) {
            try await pruner.sweep(now: now)
        }
    }

    @Test("whenMultipleCapsViolated_evictsUntilAllSatisfied")
    func whenMultipleCapsViolated_evictsUntilAllSatisfied() async throws {
        let store = MockRetentionStore()
        // 3 items, maxItemCount 2 and maxAge 60s — both caps trigger on the oldest item.
        let policy = RetentionPolicy(maxAge: 60, maxItemCount: 2, maxTotalBytes: 1_000_000_000)
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        await store.set(candidates: [
            (id1, now.addingTimeInterval(-90), 100),
            (id2, now.addingTimeInterval(-30), 100),
            (id3, now.addingTimeInterval(-10), 100)
        ])
        let pruner = RetentionPruner(policy: policy, store: store)
        try await pruner.sweep(now: now)

        let deleted = await store.deletedIDs
        #expect(deleted == [id1])
    }

    @Test("whenExpiredItemsExist_sweepDeletesThem")
    func whenExpiredItemsExist_sweepDeletesThem() async throws {
        let store = MockRetentionStore()
        let expired = UUID()
        let alive = UUID()
        await store.set(expiredIDs: [expired])
        // alive item is not in expiredIDs — won't be deleted
        _ = alive
        let pruner = RetentionPruner(store: store)
        try await pruner.sweep(now: now)

        let deleted = await store.deletedIDs
        #expect(deleted.contains(expired))
    }

    @Test("whenNoExpiredItems_noAdditionalDeletion")
    func whenNoExpiredItems_noAdditionalDeletion() async throws {
        let store = MockRetentionStore()
        let pruner = RetentionPruner(store: store)
        try await pruner.sweep(now: now)

        let deleted = await store.deletedIDs
        #expect(deleted.isEmpty)
    }

    @Test("sweep_deletesBothPolicyEvictionsAndExpiredItems")
    func sweep_deletesBothPolicyEvictionsAndExpiredItems() async throws {
        let store = MockRetentionStore()
        let policy = RetentionPolicy(maxAge: 60, maxItemCount: 1000, maxTotalBytes: 1_000_000_000)
        let tooOldID = UUID()
        let expiredID = UUID()
        await store.set(candidates: [(tooOldID, now.addingTimeInterval(-120), 100)])
        await store.set(expiredIDs: [expiredID])
        let pruner = RetentionPruner(policy: policy, store: store)
        try await pruner.sweep(now: now)

        let deleted = await store.deletedIDs
        #expect(deleted.contains(tooOldID))
        #expect(deleted.contains(expiredID))
    }

    @Test("a sweep reads the store once and deletes in one call")
    func sweep_readsOnceAndDeletesOnce() async throws {
        let store = MockRetentionStore()
        let policy = RetentionPolicy(maxAge: 60, maxItemCount: 1000, maxTotalBytes: 1_000_000_000)
        await store.set(candidates: [(UUID(), now.addingTimeInterval(-120), 100)])
        await store.set(expiredIDs: [UUID()])
        try await RetentionPruner(policy: policy, store: store).sweep(now: now)

        #expect(await store.snapshotReads == 1)
        #expect(await store.deleteCalls == 1)
    }

    @Test("a sweep with nothing to delete reads once and does not delete")
    func sweep_idleReadsOnceDeletesNever() async throws {
        let store = MockRetentionStore()
        try await RetentionPruner(store: store).sweep(now: now)

        #expect(await store.snapshotReads == 1)
        #expect(await store.deleteCalls == 0)
    }

    @Test("an item that is both too old and expired is deleted once")
    func sweep_deletesAnIDOnlyOnce() async throws {
        let store = MockRetentionStore()
        let policy = RetentionPolicy(maxAge: 60, maxItemCount: 1000, maxTotalBytes: 1_000_000_000)
        let both = UUID()
        await store.set(candidates: [(both, now.addingTimeInterval(-120), 100)])
        await store.set(expiredIDs: [both])
        try await RetentionPruner(policy: policy, store: store).sweep(now: now)

        #expect(await store.deletedIDs == [both])
    }
}

// MARK: - Helpers

private extension MockRetentionStore {
    // swiftlint:disable:next large_tuple
    func set(candidates: [(UUID, Date, Int)]) {
        self.candidates = candidates
    }

    func set(shouldThrow: Bool) {
        self.shouldThrow = shouldThrow
    }

    func set(expiredIDs: [UUID]) {
        self.expiredIDs = expiredIDs
    }
}
