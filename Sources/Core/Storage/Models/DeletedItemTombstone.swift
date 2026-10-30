// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// Tracks intentional per-item deletions so imports and restores can skip UUIDs the user has explicitly removed. Only
/// `StorageService.DeletionReason.user` (context menu, keyboard Delete, burn-after-paste) inserts tombstones; the
/// retention pruner, Clear Everything and a restore do not, because those aren't a statement of "I never want this
/// item again." Tombstones are forgotten after `StorageService.tombstoneLifetime`.
@Model
public final class DeletedItemTombstone {
    @Attribute(.unique) public var id: UUID
    public var deletedAt: Date
    /// Sync (ADR 0018): the plain SHA-256 of what was deleted (read before the clip went), so another Mac can remove
    /// its own copy of the same text under a different id; the stamp of the deletion; "item" or "collection".
    public var plainHash: String?
    public var changeClock: String?
    public var kindRaw: String?
    public var syncDirty: Bool?

    public init(id: UUID, deletedAt: Date = .now) {
        self.id = id
        self.deletedAt = deletedAt
    }
}
