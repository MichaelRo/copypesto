// SPDX-License-Identifier: MIT
import Foundation

/// Retention caps. The pruner enforces all three; pinned items are always exempt.
public struct RetentionPolicy: Sendable, Equatable {
    public var maxAge: TimeInterval
    public var maxItemCount: Int
    public var maxTotalBytes: Int

    public static let `default` = RetentionPolicy(
        maxAge: TimeInterval(Setting.retentionDays.defaultValue) * 24 * 60 * 60,
        maxItemCount: Setting.retentionMaxItems.defaultValue,
        maxTotalBytes: 2 * 1024 * 1024 * 1024
    )

    public init(maxAge: TimeInterval, maxItemCount: Int, maxTotalBytes: Int) {
        self.maxAge = maxAge
        self.maxItemCount = maxItemCount
        self.maxTotalBytes = maxTotalBytes
    }

    /// The policy the user chose in Settings (`retentionDays`, `retentionMaxItems`), clamped to the ranges the pickers
    /// allow. Zero days means keep forever. Unset keys fall back to the defaults.
    public static func fromDefaults(_ defaults: UserDefaults) -> RetentionPolicy {
        chosen(
            days: defaults.hasValue(for: Setting.retentionDays) ? defaults.value(for: Setting.retentionDays) : nil,
            maxItems: defaults.hasValue(for: Setting.retentionMaxItems)
                ? defaults.value(for: Setting.retentionMaxItems) : nil
        )
    }

    public static func chosen(days: Int?, maxItems: Int?) -> RetentionPolicy {
        let days = days.map { $0 == RetentionChoices.foreverDays ? $0 : min(max($0, 1), 365) }
            ?? Int(Self.default.maxAge / 86_400)
        return RetentionPolicy(
            maxAge: days == RetentionChoices.foreverDays ? .infinity : Double(days) * 86_400,
            maxItemCount: maxItems.map { min(max($0, 100), 10_000) } ?? Self.default.maxItemCount,
            maxTotalBytes: Self.default.maxTotalBytes
        )
    }
}

/// What Settings offers for how long and how many clips to keep.
public enum RetentionChoices {
    public static let foreverDays = 0
    public static let ageDays = [1, 7, 30, 90, 180, 365, foreverDays]
    public static let itemCounts = [500, 1000, 2500, 5000, 10_000]

    public static func isPresetAge(_ days: Int) -> Bool {
        ageDays.contains(days)
    }

    public static func isPresetCount(_ count: Int) -> Bool {
        itemCounts.contains(count)
    }
}

// swiftlint:disable large_tuple
/// What one sweep needs from the store, read together so the history is fetched once.
public struct RetentionSnapshot: Sendable {
    /// Items that are candidates for eviction, oldest first. Pinned items are not included.
    /// Each tuple is `(id, timestamp, byteSize)`.
    public let candidates: [(UUID, Date, Int)]
    /// IDs of unpinned items whose per-item `expiresAt` has passed.
    public let expired: [UUID]

    public init(candidates: [(UUID, Date, Int)], expired: [UUID]) {
        self.candidates = candidates
        self.expired = expired
    }
}

/// A minimal interface the pruner uses to evaluate retention against the store.
/// The actual SwiftData-backed implementation lives in the Xcode-side target
/// (`Sources/Core/Storage/Models/` is excluded from PestoCore for SwiftData macro reasons).
public protocol RetentionStore: Sendable {
    func retentionSnapshot(expiringBefore: Date) async throws -> RetentionSnapshot

    /// Remove the items with these IDs from storage. Implementations cascade-delete the blob.
    func deleteItems(ids: [UUID]) async throws
}

public actor RetentionPruner {
    public let store: any RetentionStore
    private let policyProvider: @Sendable () -> RetentionPolicy

    /// Asks for the policy on every sweep, so a change in Settings applies without a relaunch.
    public init(store: any RetentionStore, policyProvider: @escaping @Sendable () -> RetentionPolicy) {
        self.store = store
        self.policyProvider = policyProvider
    }

    public init(policy: RetentionPolicy = .default, store: any RetentionStore) {
        self.init(store: store, policyProvider: { policy })
    }

    /// Compute the IDs to evict given the current store state and a wall-clock `now`.
    /// Pure function — exposed for testing.
    public static func computeEvictions(
        candidates: [(UUID, Date, Int)],
        policy: RetentionPolicy,
        now: Date
    )
    -> [UUID] {
        var evictions: [UUID] = []
        var remainingCount = candidates.count
        var remainingBytes = candidates.reduce(0) { $0 + $1.2 }
        let ageCutoff = now.addingTimeInterval(-policy.maxAge)

        // candidates is expected to be ordered oldest-first.
        for (id, timestamp, size) in candidates {
            let tooOld = timestamp < ageCutoff
            let tooMany = remainingCount > policy.maxItemCount
            let tooBig = remainingBytes > policy.maxTotalBytes
            guard tooOld || tooMany || tooBig else { continue }
            evictions.append(id)
            remainingCount -= 1
            remainingBytes -= size
        }
        return evictions
    }

    /// Removes what the policy and the clips' own expiry say should go, and returns how many that was.
    @discardableResult
    public func sweep(now: Date = .now) async throws -> Int {
        let sweeping = PerfSignposts.shelf.begin("retentionSweep")
        defer { sweeping.end() }
        let policy = policyProvider()
        let snapshot = try await store.retentionSnapshot(expiringBefore: now)
        // Policy-based evictions (maxAge / maxItemCount / maxTotalBytes), then the per-item TTL.
        let evictions = Self.computeEvictions(candidates: snapshot.candidates, policy: policy, now: now)
        var seen = Set(evictions)
        let ids = evictions + snapshot.expired.filter { seen.insert($0).inserted }
        if !ids.isEmpty {
            try await store.deleteItems(ids: ids)
        }
        return ids.count
    }
}

// swiftlint:enable large_tuple
