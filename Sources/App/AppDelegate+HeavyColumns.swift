// SPDX-License-Identifier: MIT
import Foundation
import os

extension AppDelegate {
    /// Moves data that used to bloat every history row out of the store. Cheap when there is nothing left to move,
    /// so it runs at every launch and heals itself if a previous run could not reach the key.
    func runHeavyColumnMigration() {
        guard let service = storageService else { return }
        Task.detached(priority: .utility) {
            do {
                let icons = try await service.clearLegacyIcons()
                let images = try await service.moveLinkPreviewImages()
                let hashes = try await service.migrateContentHashes()
                if icons + images + hashes > 0 {
                    Self.logger.info("Migrated \(icons + images + hashes, privacy: .public) stored values")
                }
            } catch {
                Self.logger.error("Heavy column migration failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
