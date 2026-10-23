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

    public init(id: UUID, deletedAt: Date = .now) {
        self.id = id
        self.deletedAt = deletedAt
    }
}
