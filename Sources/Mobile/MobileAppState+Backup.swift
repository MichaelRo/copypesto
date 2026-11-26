// SPDX-License-Identifier: MIT
import Foundation
import os
import PestoCore

private let backupLogger = Logger(subsystem: AppIdentity.logSubsystem, category: "MobileBackup")

/// A backup written to the temporary folder, waiting for the person to choose where it goes in Files.
struct MobileBackupFile: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let sequence: UInt64
    /// Shown before the file is saved: the key was just made, or the file opens with nothing else.
    let recoveryKey: String?
    let summary: BackupExportSummary
}

/// The backup the person asks for by hand on iPhone and iPad (ADR 0078): written with the format and key store the
/// Mac uses (ADR 0010), handed to Files, and restored from any `.pestobackup`, a Mac's included.
extension MobileAppState {
    static func makeBackupKeyStore(mode: LaunchMode = .current) -> BackupKeyStore {
        mode.usesSystemIntegrations ? BackupKeyStore() : BackupKeyStore(secrets: InMemorySecretStore())
    }

    var hasBackupKey: Bool {
        (try? backupKeyStore.existingKey()) != nil
    }

    func backUp(
        protection: AutoBackupSettings.Protection, passphrase: String, includeHidden: Bool,
        iterations: Int = BackupKeyDerivation.defaultIterations
    ) async
    -> MobileBackupFile? {
        guard !isHistoryLockedNow(), let container = historyContainer else { return nil }
        guard storeIsOnDisk else {
            tell(BackupText.notOnDisk, isProblem: true)
            return nil
        }
        if protection == .passphrase, !PassphraseStrength.evaluate(passphrase).isAcceptable { return nil }
        let hold = backgroundWork.hold("Back up Pesto")
        defer { hold.finish() }
        var written: URL?
        do {
            let (key, isNew) = try backupKeyStore.keyCreatingIfNeeded()
            // Recovery key only: the header is locked with a random value nobody keeps, as on the Mac.
            let secret = protection == .passphrase ? passphrase : BackupKey.generate().recoveryKey
            let header = try await Task.detached(priority: .userInitiated) {
                try BackupFile.makeHeader(key: key, passphrase: secret, iterations: iterations)
            }.value
            let now = clock()
            let deviceID = DeviceIdentity.current()
            let name = AutoBackupSettings.exportFileName(device: DeviceName.current(), deviceID: deviceID, date: now)
            let url = try ShareFile.reserve(
                fileName: (name as NSString).deletingPathExtension, fileExtension: BackupFileType.fileExtension
            )
            written = url
            let sequence = UInt64(max(0, AppDefaults.store.integer(forKey: BackupCoordinator.sequenceKey))) + 1
            let result = try await ManualBackupWriter(container: container, storeIsOnDisk: storeIsOnDisk).write(
                to: url, key: key, header: header, includeSensitive: includeHidden,
                origin: BackupOrigin(sequence: sequence, deviceID: deviceID, createdAt: now)
            )
            guard !isHistoryLockedNow() else {
                ShareFile.remove(url)
                return nil
            }
            return MobileBackupFile(
                url: url, sequence: sequence,
                recoveryKey: isNew || protection == .recoveryKey ? key.recoveryKey : nil,
                summary: result.summary
            )
        } catch {
            if let written { ShareFile.remove(written) }
            backupLogger.error("Backup failed: \(error.localizedDescription, privacy: .public)")
            if !isHistoryLockedNow() { tell(BackupText.backUpFailed, isProblem: true) }
            return nil
        }
    }

    /// Files saved the copy: this device's sequence moves on, so a restore of an older one of its backups warns.
    func backupSaved(_ file: MobileBackupFile) {
        let defaults = AppDefaults.store
        if file.sequence > UInt64(max(0, defaults.integer(forKey: BackupCoordinator.sequenceKey))) {
            defaults.set(Int(file.sequence), forKey: BackupCoordinator.sequenceKey)
        }
        defaults.set(clock(), for: Setting.lastManualBackup)
        ShareFile.remove(file.url)
        tell(BackupText.saved(file.summary))
    }

    func backupNotSaved(_ file: MobileBackupFile) {
        ShareFile.remove(file.url)
    }

    /// Opens and authenticates every chunk of the file, changing nothing. A file in iCloud Drive that is not on this
    /// device yet is downloaded first.
    func openBackup(at url: URL, credential: BackupCredential) async throws -> BackupPreview {
        guard !isHistoryLockedNow(), let container = historyContainer else { throw CancellationError() }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try await Task.detached(priority: .userInitiated) { try Self.bringDown(url) }.value
        // `VerifiedBackup` keeps the descriptor open, so the restore still reads it after access ends.
        return try await BackupCoordinator(container: container).open(url, credential: credential)
    }

    func restorePreview(_ preview: BackupPreview) async -> BackupRestorePreview? {
        guard !isHistoryLockedNow(), let container = historyContainer else { return nil }
        return try? await BackupCoordinator(container: container).restorePreview(preview)
    }

    func restoreBackup(_ preview: BackupPreview) async -> BackupRestoreSummary? {
        guard !isHistoryLockedNow(), let container = historyContainer else { return nil }
        guard storeIsOnDisk else {
            tell(BackupText.notOnDisk, isProblem: true)
            return nil
        }
        let hold = backgroundWork.hold("Restore Pesto")
        defer { hold.finish() }
        do {
            let summary = try await BackupCoordinator(container: container).restore(preview)
            if summary.restored > 0 || summary.removedByTombstone > 0 {
                writeQuickInsert()
                await writeWidget()
                startSimilarityWork()
            }
            return summary
        } catch {
            backupLogger.error("Restore failed: \(error.localizedDescription, privacy: .public)")
            if !isHistoryLockedNow() { tell(BackupText.restoreFailed, isProblem: true) }
            return nil
        }
    }

    /// The recovery key of this device's backups, after a fresh Face ID, Touch ID or passcode.
    func revealBackupRecoveryKey() async -> String? {
        guard !isHistoryLockedNow(), await HistoryLockPolicy.permitsSensitiveAction(
            using: historyLock.authenticator, reason: String(localized: "Show the recovery key for Pesto backups"),
            requireFresh: true, grace: historyLock.grace
        ) else { return nil }
        return try? backupKeyStore.existingKey()?.recoveryKey
    }

    private nonisolated static func bringDown(_ url: URL) throws {
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinatorError) { _ in }
        if let coordinatorError { throw coordinatorError }
    }
}
