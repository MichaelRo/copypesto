// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

public struct BackupPreview: Sendable {
    public let backup: VerifiedBackup
    public let warning: RestoreWarning?

    public var itemCount: Int {
        backup.itemCount
    }

    public var collectionCount: Int {
        backup.collectionCount
    }

    public var deletionCount: Int {
        backup.deletionCount
    }

    public var settingsData: Data? {
        backup.settingsData
    }

    public var createdAt: Date {
        backup.manifest.createdAt
    }
}

/// Restores from a backup file: opens it with a passphrase or the recovery key, and flags a backup older than the
/// latest this Mac wrote (`AutoBackupService` keeps that sequence) before it is mixed in.
@MainActor
public final class BackupCoordinator {
    public static let sequenceKey = "backupSequence"

    private let container: ModelContainer
    private let defaults: UserDefaults
    private let deviceID: () -> String

    public init(
        container: ModelContainer,
        defaults: UserDefaults = AppDefaults.store,
        deviceID: @escaping () -> String = { DeviceIdentity.current() }
    ) {
        self.container = container
        self.defaults = defaults
        self.deviceID = deviceID
    }

    public func open(_ url: URL, credential: BackupCredential) async throws -> BackupPreview {
        let backup = try await Task.detached(priority: .userInitiated) {
            try BackupFile.verify(url: url, credential: credential)
        }.value
        let warning = RestoreWarning.evaluate(
            manifest: backup.manifest, lastLocalSequence: UInt64(defaults.integer(forKey: Self.sequenceKey)),
            localDeviceID: deviceID()
        )
        return BackupPreview(backup: backup, warning: warning)
    }

    /// What `restore` would do, counted without writing anything.
    public func restorePreview(_ preview: BackupPreview) async throws -> BackupRestorePreview {
        try await StorageService(modelContainer: container).previewRestore(preview.backup)
    }

    public func restore(_ preview: BackupPreview) async throws -> BackupRestoreSummary {
        try await StorageService(modelContainer: container).restore(preview.backup)
    }

    /// Restores in place of a history that cannot be read: `discard` runs first and only now, with the backup already
    /// opened and confirmed. A discard that throws restores nothing.
    public func restore(
        _ preview: BackupPreview, replacing discard: @MainActor () throws -> Void
    ) async throws
    -> BackupRestoreSummary {
        try discard()
        return try await restore(preview)
    }
}
