// SPDX-License-Identifier: MIT
import Foundation
import os
import SwiftData

private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "AutoBackup")

public enum AutoBackupError: Error, Equatable {
    case backupAlreadyInFolder
}

/// Keeps one encrypted backup of this Mac's history in a folder the person chose, such as a folder in iCloud Drive,
/// and rewrites it a few minutes after the history changes (`AutoBackupPolicy`). It is off until the person turns it
/// on,
/// per Mac. It only writes: restoring stays a deliberate act in Settings, and nothing here reads other Macs' files.
@MainActor
public final class AutoBackupService {
    public enum Outcome: Equatable, Sendable {
        case written(bytes: Int, skippedLarge: Int)
        case needsSetup
        case folderUnavailable
        case failed
        case refused(AutoBackupRefusal)
    }

    private let container: ModelContainer
    private let settings: AutoBackupSettings
    private let keyStore: BackupKeyStore
    private let defaults: UserDefaults
    private let deviceID: () -> String
    private let macName: () -> String
    private let isPersistentStore: Bool
    private let verifyWritten: @Sendable (URL, BackupKey) throws -> Void
    private var observer: (any NSObjectProtocol)?
    private var settingsObserver: (any NSObjectProtocol)?
    private var settingsFingerprint = ""
    private var pending: Task<Void, Never>?
    private var inFlight: Task<Outcome, Never>?
    private var lastChange: Date?
    /// Read from the Keychain once per launch: every read can ask the person for their password on a build whose
    /// signature the item does not know, and a backup runs many times a day.
    private var cachedKey: BackupKey?
    public private(set) var isRunning = false
    /// The clips the last run could not read. They block every backup until they are removed (or become readable).
    public private(set) var unreadableClipIDs: [UUID] = []

    public init(
        container: ModelContainer,
        settings: AutoBackupSettings = AutoBackupSettings(),
        keyStore: BackupKeyStore = BackupKeyStore(),
        defaults: UserDefaults = AppDefaults.store,
        deviceID: @escaping () -> String = { DeviceIdentity.current() },
        macName: @escaping () -> String = { Host.current().localizedName ?? "Mac" },
        isPersistentStore: Bool = true,
        verifyWritten: @escaping @Sendable (URL, BackupKey) throws -> Void = { url, key in
            _ = try BackupFile.verify(url: url, credential: .recoveryKey(key))
        }
    ) {
        self.verifyWritten = verifyWritten
        self.container = container
        self.settings = settings
        self.keyStore = keyStore
        self.defaults = defaults
        self.deviceID = deviceID
        self.macName = macName
        self.isPersistentStore = isPersistentStore
    }

    /// Starts watching when the person has it switched on, and stops when they have not. Safe to call at any time.
    public func refresh() {
        if settings.isEnabled, settings.runsAutomatically { start() } else { stop() }
    }

    /// The person's switch for keeping the backup up to date by itself. Back Up Now works either way.
    public func setAutomatic(_ on: Bool) {
        settings.runsAutomatically = on
        refresh()
    }

    private func start() {
        guard !isRunning else { return }
        isRunning = true
        observer = ModelSaveObserver.observe { [weak self] in self?.noteChange() }
        settingsFingerprint = SettingsBackupManager.fingerprint(in: defaults)
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsMayHaveChanged() }
        }
        if settings.lastBackup == nil { noteChange() }
    }

    /// The backup carries the settings, so a change to one is a reason to back up. Only the settings it carries count:
    /// the backup's own bookkeeping is written to the same preferences and must not start another backup.
    private func settingsMayHaveChanged() {
        let current = SettingsBackupManager.fingerprint(in: defaults)
        guard current != settingsFingerprint else { return }
        settingsFingerprint = current
        noteChange()
    }

    public func stop() {
        isRunning = false
        pending?.cancel()
        pending = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        settingsObserver = nil
    }

    public func noteChange(now: Date = .now) {
        lastChange = now
        schedule(now: now)
    }

    private func schedule(now: Date) {
        pending?.cancel()
        let lastBackup = settings.lastBackup
        guard let delay = AutoBackupPolicy.delay(lastChange: lastChange, lastBackup: lastBackup, now: now) else {
            return
        }
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            _ = await self?.backUpNow()
        }
    }

    /// Writes the backup now. Used by the timer and by Back Up Now. It never replaces the file with a history that
    /// looks broken (see `AutoBackupGuard`), and keeps the file it replaces as the previous generation.
    @discardableResult
    public func backUpNow(allowShrink: Bool = false) async -> Outcome {
        // The timer and Back Up Now can both ask while a run is still streaming; both write the same partial file, so
        // each run waits for the one before it.
        let previous = inFlight
        let run = Task { [self] in
            _ = await previous?.value
            return await writeBackup(allowShrink: allowShrink)
        }
        inFlight = run
        let outcome = await run.value
        if inFlight == run { inFlight = nil }
        rememberProblem(of: outcome)
        return outcome
    }

    /// Keeps what went wrong where Settings can read it without the Keychain; a written backup clears it, and a run
    /// that was never set up leaves it alone.
    private func rememberProblem(of outcome: Outcome) {
        switch outcome {
        case .written: settings.problem = nil
        case .folderUnavailable: settings.problem = .folderMissing
        case .failed: settings.problem = .failed
        case .refused: settings.problem = .refused
        case .needsSetup: break
        }
    }

    private func writeBackup(allowShrink: Bool) async -> Outcome {
        guard settings.isEnabled, let folder = settings.folder else { return .needsSetup }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue else
        {
            return .folderUnavailable
        }
        guard isPersistentStore else { return refuse(.storeNotOnDisk) }
        do {
            guard let key = try backupKey(), let header = settings.header else { return .needsSetup }
            let target = backupFile(in: folder)
            let legacy = folder.appendingPathComponent(AutoBackupSettings.legacyFileName(forMac: macName()))
            await Task.detached(priority: .utility) { Self.adoptOldNamedFile(legacy, as: target, key: key) }.value
            // Written record by record to a partial file next to the target, so the history is never all in memory and
            // the existing backup is replaced only when the new one is complete and has passed the guard.
            let partial = target.appendingPathExtension("partial")
            try? FileManager.default.removeItem(at: partial)
            let writer = try BackupFile.StreamingWriter(url: partial, key: key, header: header)
            let summary: BackupExportSummary
            do {
                if let settingsJSON = try? SettingsBackupManager.export(from: defaults) {
                    try writer.append(.settings(settingsJSON))
                }
                summary = try await StorageService(modelContainer: container).streamBackupRecords(
                    includeSensitive: settings.includesSecrets, sink: { try writer.append($0) }
                )
            } catch {
                writer.abandon()
                try? FileManager.default.removeItem(at: partial)
                throw error
            }
            unreadableClipIDs = summary.unreadableIDs
            let usesAnotherKey = await Task.detached(priority: .utility) {
                Self.fileUsesAnotherKey(target, key: key)
            }.value
            if let refusal = AutoBackupGuard.refusal(
                storeIsOnDisk: isPersistentStore, unreadable: summary.skippedUnreadable,
                clips: summary.items, lastClips: settings.lastClipCount, allowShrink: allowShrink,
                pausedAfterClear: settings.pausedAfterClear,
                fileUsesAnotherKey: usesAnotherKey
            ) {
                writer.abandon()
                try? FileManager.default.removeItem(at: partial)
                return refuse(refusal)
            }
            let sequence = UInt64(defaults.integer(forKey: BackupCoordinator.sequenceKey)) + 1
            let bytes = try writer.finish(origin: BackupOrigin(
                sequence: sequence,
                deviceID: deviceID(),
                createdAt: .now
            ))
            try await commit(partial, over: target, key: key)
            recordWritten(summary, bytes: bytes, sequence: sequence, confirmedShrink: allowShrink)
            return .written(bytes: bytes, skippedLarge: summary.skippedTooLarge)
        } catch {
            logger.error("Automatic backup failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    private func recordWritten(_ summary: BackupExportSummary, bytes: Int, sequence: UInt64, confirmedShrink: Bool) {
        defaults.set(Int(sequence), forKey: BackupCoordinator.sequenceKey)
        settings.lastBackup = .now
        settings.lastBytes = bytes
        settings.lastSkippedLarge = summary.skippedTooLarge
        settings.lastClipCount = AutoBackupGuard.nextBaseline(
            previous: settings.lastClipCount, written: summary.items, confirmed: confirmedShrink
        )
        settings.pausedAfterClear = false
        lastChange = nil
    }

    /// What Clear Everything does about the backup. Kept: automatic backup stops replacing the file until the person
    /// confirms with Back Up Now, so the old history stays restorable. Deleted: the file and its previous copy go too.
    public func afterClearEverything(deleteBackup: Bool) {
        guard settings.isEnabled else { return }
        guard deleteBackup else {
            settings.pausedAfterClear = true
            return
        }
        settings.pausedAfterClear = false
        settings.lastClipCount = nil
        guard let folder = settings.folder else { return }
        let file = backupFile(in: folder)
        let previous = file.deletingPathExtension().appendingPathExtension("previous.pestobackup")
        let legacy = folder.appendingPathComponent(AutoBackupSettings.legacyFileName(forMac: macName()))
        let legacyPrevious = legacy.deletingPathExtension().appendingPathExtension("previous.pestobackup")
        for url in [file, previous, legacy, legacyPrevious] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Removes the clips the last run could not read, so they stop blocking the backup. Not a statement that they must
    /// not come back: an earlier backup that holds a readable copy can still restore it.
    @discardableResult
    public func deleteUnreadableClips() async -> Int {
        let ids = unreadableClipIDs
        guard !ids.isEmpty else { return 0 }
        let removed = await (
            try? StorageService(modelContainer: container).deleteItems(ids: ids, reason: .unreadable)
        ) ??
            0
        if removed > 0 { unreadableClipIDs = [] }
        return removed
    }

    private func refuse(_ refusal: AutoBackupRefusal) -> Outcome {
        logger.error("Backup refused: \(String(describing: refusal), privacy: .public)")
        if !unreadableClipIDs.isEmpty {
            let ids = unreadableClipIDs.map(\.uuidString).joined(separator: ", ")
            logger.error("Unreadable clips: \(ids, privacy: .private)")
        }
        return .refused(refusal)
    }

    private func backupFile(in folder: URL) -> URL {
        folder.appendingPathComponent(AutoBackupSettings.fileName(forMac: macName(), deviceID: deviceID()))
    }

    /// A file under the name used before device ids were added belongs to this Mac only when it was written under
    /// this Mac's key; a same-named file from another Mac is left alone. When the new-named file already exists,
    /// the duplicate legacy file is removed.
    private nonisolated static func adoptOldNamedFile(_ legacy: URL, as target: URL, key: BackupKey) {
        guard legacy != target, FileManager.default.fileExists(atPath: legacy.path),
              let handle = try? FileHandle(forReadingFrom: legacy) else { return }
        let start = try? handle.read(upToCount: 4096)
        try? handle.close()
        guard let start, let legacyHeader = BackupFile.header(of: start),
              BackupFile.header(legacyHeader, isWrittenWith: key) else { return }
        let legacyPrevious = legacy.deletingPathExtension().appendingPathExtension("previous.pestobackup")
        if FileManager.default.fileExists(atPath: target.path) {
            try? FileManager.default.removeItem(at: legacy)
            try? FileManager.default.removeItem(at: legacyPrevious)
        } else {
            try? FileManager.default.moveItem(at: legacy, to: target)
            try? FileManager.default.removeItem(at: legacyPrevious)
        }
    }

    /// True when a backup file is already there and this Mac's key does not open it: a file left by an earlier key or
    /// copied in from another Mac. An unreadable or foreign file counts too, because replacing it cannot be undone.
    private nonisolated static func fileUsesAnotherKey(_ target: URL, key: BackupKey) -> Bool {
        guard FileManager.default.fileExists(atPath: target.path) else { return false }
        guard let handle = try? FileHandle(forReadingFrom: target) else { return true }
        defer { try? handle.close() }
        guard let start = try? handle.read(upToCount: 4096),
              let header = BackupFile.header(of: start) else { return true }
        return !BackupFile.header(header, isWrittenWith: key)
    }

    /// Verifies the finished file, keeps what it replaces as the previous generation and swaps it in, off the main
    /// actor. A file that does not verify never replaces the good one.
    private func commit(_ partial: URL, over target: URL, key: BackupKey) async throws {
        let verify = verifyWritten
        do {
            try await Task.detached(priority: .utility) {
                try verify(partial, key)
                try Self.keepPreviousGeneration(of: target)
                try Self.replace(target, with: partial)
            }.value
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
    }

    private nonisolated static func replace(_ target: URL, with partial: URL) throws {
        if FileManager.default.fileExists(atPath: target.path) {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: partial)
        } else {
            try FileManager.default.moveItem(at: partial, to: target)
        }
    }

    private nonisolated static func keepPreviousGeneration(of target: URL) throws {
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        let previous = target.deletingPathExtension().appendingPathExtension("previous.pestobackup")
        try? FileManager.default.removeItem(at: previous)
        try FileManager.default.copyItem(at: target, to: previous)
    }

    /// When the next automatic backup will run, or nil when nothing has changed since the last one.
    public var nextBackup: Date? {
        AutoBackupPolicy.nextBackup(lastChange: lastChange, lastBackup: settings.lastBackup, now: .now)
    }

    /// Switches it on: a header is made for this passphrase and kept, so later backups need no passphrase, the folder
    /// is remembered, and the first backup is written. With no passphrase the header is locked with a random one that
    /// is
    /// thrown away, so only the recovery key opens the file; the recovery key is then returned every time, because it
    /// is the only way in. With a passphrase it is returned only when the key is new.
    public func enable(
        passphrase: String?,
        folder: URL,
        includeSensitive: Bool,
        automatic: Bool = true,
        iterations: Int = BackupKeyDerivation.defaultIterations
    ) async throws
    -> (recoveryKey: String?, outcome: Outcome) {
        if try keyStore.existingKey() == nil, backupExists(in: folder) { throw AutoBackupError.backupAlreadyInFolder }
        let (key, isNew) = try keyStore.keyCreatingIfNeeded()
        cachedKey = key
        let secret = passphrase ?? BackupKey.generate().recoveryKey
        let header = try await Task.detached(priority: .userInitiated) {
            try BackupFile.makeHeader(key: key, passphrase: secret, iterations: iterations)
        }.value
        settings.header = header
        settings.folder = folder
        settings.includesSecrets = includeSensitive
        settings.protection = passphrase == nil ? .recoveryKey : .passphrase
        settings.runsAutomatically = automatic
        settings.isEnabled = true
        refresh()
        let outcome = await backUpNow()
        return (isNew || passphrase == nil ? key.recoveryKey : nil, outcome)
    }

    private func backupExists(in folder: URL) -> Bool {
        [backupFile(in: folder), folder.appendingPathComponent(AutoBackupSettings.legacyFileName(forMac: macName()))]
            .contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func backupKey() throws -> BackupKey? {
        if let cachedKey { return cachedKey }
        cachedKey = try keyStore.existingKey()
        return cachedKey
    }

    public func disable() {
        cachedKey = nil
        settings.turnOff()
        stop()
    }
}
