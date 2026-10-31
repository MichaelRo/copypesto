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

/// Opens the SwiftData store used at runtime: **clips.store** (`ClipboardItem`, `ClipboardBlob`,
/// `DeletedItemTombstone`, `Pinboard`), the history, at
/// `~/Library/Application Support/net.copypesto.pesto/clips.store`. CloudKit is never used: sync is the encrypted
/// folder (ADR 0018). `StorageBoot.run` decides what happens when it will not open.
public enum ModelContainerSetup {
    private static func supportDirectory() throws -> URL {
        let appSupport = AppPaths.supportDirectory
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport
    }

    public static func openClips(storeURL: URL? = nil) throws -> ModelContainer {
        let url = try storeURL ?? supportDirectory().appendingPathComponent("clips.store")
        return try ModelContainer(
            for: Schema(versionedSchema: PestoSchemaV1.self),
            migrationPlan: PestoMigrationPlan.self,
            configurations: ModelConfiguration("clips", url: url, cloudKitDatabase: .none)
        )
    }

    /// Earlier versions made a `local.store` that nothing ever read; it is removed so it does not sit in Application
    /// Support for good.
    public static func removeRetiredStores(in directory: URL = AppPaths.supportDirectory) {
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("local.store\(suffix)"))
        }
    }

    /// An in-memory container for unit and integration tests. Does not touch disk.
    public static func makeInMemory() throws -> ModelContainer {
        try ModelContainer(
            for: ClipboardItem.self, ClipboardBlob.self, DeletedItemTombstone.self, Pinboard.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}
