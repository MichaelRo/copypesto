// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// The shipped schema, as version 1. A later release that changes a model adds a V2 and a migration stage here, so an
/// existing install migrates instead of failing to open its store.
enum PestoSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [ClipboardItem.self, ClipboardBlob.self, DeletedItemTombstone.self, Pinboard.self]
    }
}

enum PestoMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PestoSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

/// Opens the SwiftData stores used at runtime.
///
/// - **clips.store** (`ClipboardItem`, `ClipboardBlob`, `DeletedItemTombstone`, `Pinboard`): the history. CloudKit is
///   never used: sync is the encrypted folder (ADR 0018). Lives at
///   `~/Library/Application Support/net.copypesto.pesto/clips.store`.
/// - **local.store**: kept for forward-compatibility; nothing reads it, so `StorageBoot` treats it as best effort.
///
/// `StorageBoot.run` decides what happens when one of them will not open.
public enum ModelContainerSetup {
    private static func supportDirectory() throws -> URL {
        let appSupport = AppPaths.supportDirectory
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport
    }

    public static func openSynced(cloudKitEnabled: Bool, storeURL: URL? = nil) throws -> ModelContainer {
        let url = try storeURL ?? supportDirectory().appendingPathComponent("clips.store")
        let useCloudKit = cloudKitEnabled && RuntimeConfiguration.current.mode.usesSystemIntegrations
        let configuration = ModelConfiguration(
            "clips", url: url, cloudKitDatabase: useCloudKit ? .private("iCloud.\(AppIdentity.bundleID)") : .none
        )
        return try ModelContainer(
            for: Schema(versionedSchema: PestoSchemaV1.self),
            migrationPlan: PestoMigrationPlan.self,
            configurations: configuration
        )
    }

    public static func openLocal(storeURL: URL? = nil) throws -> ModelContainer {
        let url = try storeURL ?? supportDirectory().appendingPathComponent("local.store")
        return try ModelContainer(
            for: Pinboard.self, configurations: ModelConfiguration("local", url: url, cloudKitDatabase: .none)
        )
    }

    /// In-memory containers for unit/integration tests. Does not touch disk or CloudKit.
    public static func makeInMemory() throws -> (synced: ModelContainer, local: ModelContainer) {
        let synced = try ModelContainer(
            for: ClipboardItem.self, ClipboardBlob.self, DeletedItemTombstone.self, Pinboard.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let local = try ModelContainer(
            for: Pinboard.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return (synced, local)
    }
}
