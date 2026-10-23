// SPDX-License-Identifier: MIT
import Foundation

public extension LaunchMigration {
    /// Every versioned migration, in the order they run. The shared storage service does the work, not a second one: a
    /// second actor and context would write to the store alongside live ingest, each with its own idea of what is
    /// there.
    static func standard(service: StorageService) -> [LaunchMigration] {
        [
            LaunchMigration(name: "Classifier migration", version: Setting.classifierVersion, currentVersion: 4) {
                try await .done("reclassified \(service.reclassifyContentTypes()) items")
            },
            LaunchMigration(name: "Preview encryption", version: Setting.previewEncryptionVersion, currentVersion: 2) {
                let migrated = try await service.giveSnippetsABlob() + service.encryptLegacyPreviews()
                return .done("\(migrated) items")
            },
            LaunchMigration(name: "Ciphertext binding", version: Setting.ciphertextBindingVersion, currentVersion: 1) {
                let result = try await service.bindCiphertextToItems()
                let summary = "\(result.converted) converted, \(result.failed) kept"
                return result.failed == 0 ? .done(summary) : .incomplete(summary)
            },
            LaunchMigration(name: "Metadata sealing", version: Setting.metadataSealingVersion, currentVersion: 1) {
                let result = try await service.sealItemMetadata()
                let summary = "\(result.sealed) sealed, \(result.failed) kept"
                return result.failed == 0 ? .done(summary) : .incomplete(summary)
            },
            LaunchMigration(name: "Vector sealing", version: Setting.embeddingSealingVersion, currentVersion: 1) {
                let result = try await service.sealEmbeddings()
                let summary = "\(result.sealed) sealed, \(result.failed) kept"
                return result.failed == 0 ? .done(summary) : .incomplete(summary)
            },
            LaunchMigration(name: "Clip repair", version: Setting.clipRepairVersion, currentVersion: 2) {
                let result = try await service.repairMisreadClips()
                return .done("\(result.reclassified) reclassified, \(result.rebuilt) rebuilt")
            },
            LaunchMigration(name: "Secret masks", version: Setting.secretMaskVersion, currentVersion: 2) {
                try await .done("\(service.modernizeSecretMasks()) masks rewritten")
            }
        ]
    }
}
