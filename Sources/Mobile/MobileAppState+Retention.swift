// SPDX-License-Identifier: MIT
import Foundation
import os
import PestoCore

/// When the retention sweep runs: at launch, on coming back to the foreground (at most once an hour, because it reads
/// every unpinned clip), and at once when the person changes how long or how many to keep.
struct RetentionSchedule: Equatable {
    static let minimumInterval: TimeInterval = 3600

    private(set) var lastSweep: Date?
    private(set) var lastPolicy: RetentionPolicy?

    func shouldSweep(now: Date, policy: RetentionPolicy, force: Bool) -> Bool {
        if force || policy != lastPolicy { return true }
        guard let lastSweep else { return true }
        return now.timeIntervalSince(lastSweep) >= Self.minimumInterval
    }

    mutating func didSweep(at date: Date, policy: RetentionPolicy) {
        lastSweep = date
        lastPolicy = policy
    }
}

/// The Mac's "Keep history for" policy on iPhone and iPad (`RetentionPolicy`, `RetentionPruner`): pinned clips are
/// never swept, and the sweep deletes through `StorageService.deleteItems`, the one way to delete.
extension MobileAppState {
    private static let retentionLogger = Logger(subsystem: AppIdentity.logSubsystem, category: "MobileRetention")

    func pruneHistory(force: Bool = false) async {
        guard let service = storageService else { return }
        let policy = retentionPolicy()
        let now = clock()
        guard retentionSchedule.shouldSweep(now: now, policy: policy, force: force) else { return }
        let pruner = RetentionPruner(store: retentionStore(service), policyProvider: retentionPolicy)
        do {
            try await pruner.sweep(now: now)
            retentionSchedule.didSweep(at: now, policy: policy)
        } catch {
            Self.retentionLogger.error("The retention sweep failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// What lowering "Keep clips for" or "Keep at most" would delete, counted before it does.
enum RetentionPreview {
    static func clipsLeaving(
        snapshot: RetentionSnapshot, current: RetentionPolicy, proposed: RetentionPolicy, now: Date
    )
    -> Int {
        let already = Set(RetentionPruner.computeEvictions(candidates: snapshot.candidates, policy: current, now: now))
        let leaving = Set(RetentionPruner.computeEvictions(candidates: snapshot.candidates, policy: proposed, now: now))
        return leaving.subtracting(already).count
    }
}

extension MobileAppState {
    func clipsLeaving(days: Int, maxItems: Int) async -> Int {
        guard let service = storageService else { return 0 }
        let now = clock()
        guard let snapshot = try? await retentionStore(service).retentionSnapshot(expiringBefore: now) else { return 0 }
        return RetentionPreview.clipsLeaving(
            snapshot: snapshot, current: retentionPolicy(), proposed: .chosen(days: days, maxItems: maxItems), now: now
        )
    }
}
