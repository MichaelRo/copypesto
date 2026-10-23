// SPDX-License-Identifier: MIT
import Foundation

/// The sweep's view of the store. Deletion goes through `StorageService.deleteItems`, the one way to delete,
/// so an expired or aged-out item leaves no plaintext behind (last-item file, Spotlight, preview cache).
public struct StorageRetentionStore: RetentionStore {
    let service: StorageService

    public init(service: StorageService) {
        self.service = service
    }

    public func retentionSnapshot(expiringBefore: Date) async throws -> RetentionSnapshot {
        try await service.retentionSnapshot(expiringBefore: expiringBefore)
    }

    public func deleteItems(ids: [UUID]) async throws {
        try await service.deleteItems(ids: ids, reason: .retention)
    }
}
