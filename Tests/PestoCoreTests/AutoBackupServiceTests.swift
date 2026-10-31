// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Synchronization
import Testing
@testable import PestoCore

@Suite("Automatic backup service", .serialized)
@MainActor
struct AutoBackupServiceTests {
    let container: ModelContainer
    let suite = UUID().uuidString
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("pesto-autobackup-\(UUID().uuidString)", isDirectory: true)

    init() throws {
        container = try ModelContainerSetup.makeInMemory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func service(
        secrets: MemorySecrets = MemorySecrets(),
        isPersistentStore: Bool = true,
        verifyWritten: (@Sendable (URL, BackupKey) throws -> Void)? = nil
    ) throws
    -> (AutoBackupService, UserDefaults) {
        let defaults = ThrowawayDefaults.make(suite)
        let service = AutoBackupService(
            container: container, settings: AutoBackupSettings(defaults: defaults),
            keyStore: BackupKeyStore(secrets: secrets), defaults: defaults, deviceID: { "mac-a" },
            macName: { "Test Mac" }, isPersistentStore: isPersistentStore,
            verifyWritten: verifyWritten ?? { url, key in _ = try BackupFile.verify(
                url: url,
                credential: .recoveryKey(key)
            ) }
        )
        return (service, defaults)
    }

    func ingest(_ text: String) async throws {
        let store = StorageService(modelContainer: container)
        let payload = Data(text.utf8)
        try await store.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: payload, payloadString: text,
            frontmostBundleID: "com.apple.Notes", timestamp: .now,
            contentHash: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        ))
    }

    var backupFile: URL {
        folder.appendingPathComponent(AutoBackupSettings.fileName(forMac: "Test Mac", deviceID: "mac-a"))
    }

    private var previousFile: URL {
        backupFile.deletingPathExtension().appendingPathExtension("previous.pestobackup")
    }

    private func clipCount(in file: URL, key: BackupKey) throws -> Int {
        try BackupFile.read(Data(contentsOf: file), credential: .recoveryKey(key)).records.count(where: {
            $0.kind == .item
        })
    }

    func clean(_: UserDefaults) {
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("the backup carries the settings, so a restore on another Mac can bring them too")
    func whenBackedUp_thenTheFileCarriesTheSettings() async throws {
        let (service, defaults) = try service()
        defer { clean(defaults) }
        defaults.set("mortar", forKey: Setting.appTheme.name)
        try await ingest("a clip")

        let result = try await service.enable(
            passphrase: "correct horse battery staple", folder: folder, includeSensitive: false, iterations: 1000
        )
        let recoveryKey = try #require(result.recoveryKey)

        let verified = try BackupFile.verify(
            url: backupFile,
            credential: .recoveryKey(BackupKey(recoveryKey: recoveryKey))
        )
        let settings = try #require(verified.settingsData)
        let payload = try #require(try JSONSerialization.jsonObject(with: settings) as? [String: Any])
        let values = try #require(payload["settings"] as? [String: Any])
        #expect(values[Setting.appTheme.name] as? String == "mortar")
        #expect(values["hasOnboarded"] == nil, "state this Mac keeps about itself is not carried")
    }

    @Test("switching it on writes the first backup, shows the recovery key once, and opens with the passphrase")
    func whenEnabled_thenFirstBackupIsWritten() async throws {
        let (service, defaults) = try service()
        defer { clean(defaults) }
        try await ingest("remember the basil")

        let result = try await service.enable(
            passphrase: "correct horse battery staple", folder: folder, includeSensitive: false, iterations: 1000
        )

        #expect(result.recoveryKey != nil)
        guard case let .written(bytes, _) = result.outcome else {
            Issue.record("not written: \(result.outcome)")
            return
        }
        #expect(bytes > 0)
        let contents = try BackupFile.read(
            Data(contentsOf: backupFile), credential: .passphrase("correct horse battery staple")
        )
        #expect(contents.records.contains { $0.kind == .item })
        service.stop()
    }

    @Test("with no passphrase the recovery key is the only way in, and it is shown even if the key already existed")
    func whenNoPassphrase_thenOnlyTheRecoveryKeyOpensTheFile() async throws {
        let secrets = MemorySecrets()
        _ = try BackupKeyStore(secrets: secrets).keyCreatingIfNeeded()
        let (service, defaults) = try service(secrets: secrets)
        defer { clean(defaults) }
        try await ingest("basil")

        let result = try await service.enable(
            passphrase: nil,
            folder: folder,
            includeSensitive: false,
            iterations: 1000
        )

        let recovery = try #require(result.recoveryKey)
        let file = try Data(contentsOf: backupFile)
        let contents = try BackupFile.read(file, credential: .recoveryKey(BackupKey(recoveryKey: recovery)))
        #expect(contents.records.contains { $0.kind == .item })
        #expect(throws: BackupError.self) { try BackupFile.read(file, credential: .passphrase("")) }
        service.stop()
    }

    @Test("with automatic backup off the backup still runs on request, and nothing runs by itself")
    func whenNotAutomatic_thenOnlyBackUpNowWrites() async throws {
        let (service, defaults) = try service()
        defer { clean(defaults) }
        try await ingest("first clip")

        let result = try await service.enable(
            passphrase: nil, folder: folder, includeSensitive: false, automatic: false, iterations: 1000
        )

        guard case .written = result.outcome else {
            Issue.record("not written: \(result.outcome)")
            return
        }
        #expect(!service.isRunning, "an off switch must not leave a watcher running")
        try await ingest("second clip")
        guard case .written = await service.backUpNow() else {
            Issue.record("Back Up Now did not write")
            return
        }
        #expect(AutoBackupSettings(defaults: defaults).protection == .recoveryKey)
        service.setAutomatic(true)
        #expect(service.isRunning)
        service.setAutomatic(false)
        #expect(!service.isRunning)
    }

    private static func finished(_ semaphore: DispatchSemaphore) -> Bool {
        semaphore.wait(timeout: .now() + 10) == .success
    }

    @Test("a preference written from another thread never waits for the main thread")
    func whenAPreferenceIsWrittenOffMain_thenTheWriterIsNotHeldByTheMainThread() async throws {
        let (service, defaults) = try service()
        defer { clean(defaults) }
        _ = try await service.enable(
            passphrase: nil, folder: folder, includeSensitive: false, automatic: true, iterations: 1000
        )
        #expect(service.isRunning)

        let written = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            defaults.set(UUID().uuidString, forKey: "pesto.test.offMainWrite")
            written.signal()
        }

        #expect(Self.finished(written), "the write waited for the main thread")
        service.stop()
    }

    @Test("the Keychain is asked for the backup key once, not for every backup")
    func whenBackedUpRepeatedly_thenTheKeychainIsReadOnce() async throws {
        let secrets = MemorySecrets()
        let (service, defaults) = try service(secrets: secrets)
        defer { clean(defaults) }
        try await ingest("first clip")
        _ = try await service.enable(passphrase: nil, folder: folder, includeSensitive: false, iterations: 1000)
        let afterEnable = secrets.readCount

        try await ingest("second clip")
        _ = await service.backUpNow()
        try await ingest("third clip")
        _ = await service.backUpNow()

        #expect(secrets.readCount == afterEnable, "a backup read the Keychain again")
        service.stop()
    }

    @Test("later backups need no passphrase, include new clips, and keep the same recovery key working")
    func whenBackedUpAgain_thenNewClipsAreIncludedWithoutAPassphrase() async throws {
        let secrets = MemorySecrets()
        let (service, defaults) = try service(secrets: secrets)
        defer { clean(defaults) }
        try await ingest("first clip")
        let first = try await service.enable(
            passphrase: "correct horse battery staple",
            folder: folder,
            includeSensitive: false,
            iterations: 1000
        )
        let key = try #require(try BackupKeyStore(secrets: secrets).existingKey())
        try await ingest("second clip")

        let outcome = await service.backUpNow()

        guard case .written = outcome else {
            Issue.record("not written: \(outcome)")
            return
        }
        let contents = try BackupFile.read(Data(contentsOf: backupFile), credential: .recoveryKey(key))
        #expect(contents.records.count(where: { $0.kind == .item }) == 2)
        #expect(first.recoveryKey == key.recoveryKey)
        service.stop()
    }

    @Test("two backups requested at once run one after the other and leave one complete file")
    func whenTwoBackupsOverlap_thenTheFileIsCompleteAndNoPartialIsLeft() async throws {
        let secrets = MemorySecrets()
        let (service, defaults) = try service(secrets: secrets)
        defer { clean(defaults) }
        for index in 0..<40 {
            try await ingest("clip number \(index)")
        }
        _ = try await service.enable(
            passphrase: "correct horse battery staple", folder: folder, includeSensitive: false, iterations: 1000
        )
        let key = try #require(try BackupKeyStore(secrets: secrets).existingKey())

        async let first = service.backUpNow()
        async let second = service.backUpNow()
        let outcomes = await [first, second]

        for outcome in outcomes {
            guard case .written = outcome else {
                Issue.record("a backup did not complete: \(outcome)")
                return
            }
        }
        #expect(try clipCount(in: backupFile, key: key) == 40)
        #expect(!FileManager.default.fileExists(atPath: backupFile.appendingPathExtension("partial").path))
        service.stop()
    }

    @Test("a new file that does not verify never replaces the good backup, and no partial is left")
    func whenTheNewFileDoesNotVerify_thenTheGoodBackupStays() async throws {
        let secrets = MemorySecrets()
        let broken = Mutex(false)
        let (service, defaults) = try service(secrets: secrets, verifyWritten: { _, _ in
            if broken.withLock({ $0 }) { throw BackupError.notABackup }
        })
        defer { clean(defaults) }
        try await ingest("first clip")
        _ = try await service.enable(
            passphrase: "correct horse battery staple", folder: folder, includeSensitive: false, iterations: 1000
        )
        let good = try Data(contentsOf: backupFile)
        try await ingest("second clip")
        broken.withLock { $0 = true }

        let outcome = await service.backUpNow()

        #expect(outcome == .failed)
        #expect(try Data(contentsOf: backupFile) == good)
        #expect(!FileManager.default.fileExists(atPath: backupFile.appendingPathExtension("partial").path))
        service.stop()
    }

    @Test("switching it off stops writing, and a missing folder is reported instead of failing quietly")
    func whenDisabledOrFolderGone_thenNothingIsWritten() async throws {
        let (service, defaults) = try service()
        defer { clean(defaults) }
        _ = try await service.enable(
            passphrase: "correct horse battery staple",
            folder: folder,
            includeSensitive: false,
            iterations: 1000
        )

        try FileManager.default.removeItem(at: folder)
        #expect(await service.backUpNow() == .folderUnavailable)

        service.disable()
        #expect(await service.backUpNow() == .needsSetup)
        #expect(AutoBackupSettings(defaults: defaults).header == nil)
    }

    @Test("clips that hold secrets are left out unless the person asked for them")
    func whenSecretsNotIncluded_thenLeftOut() async throws {
        let (service, defaults) = try service()
        defer { clean(defaults) }
        try await ingest("plain note")
        try await ingest("4111 1111 1111 1111")

        let result = try await service.enable(
            passphrase: "correct horse battery staple",
            folder: folder,
            includeSensitive: false,
            iterations: 1000
        )

        guard case .written = result.outcome else {
            Issue.record("not written")
            return
        }
        let contents = try BackupFile.read(
            Data(contentsOf: backupFile), credential: .passphrase("correct horse battery staple")
        )
        #expect(contents.records.count(where: { $0.kind == .item }) == 1)
        service.stop()
    }

    @Test("a store that is only in memory never touches the backup in the folder")
    func whenStoreIsInMemory_thenTheBackupIsLeftAlone() async throws {
        let secrets = MemorySecrets()
        let (onDisk, defaults) = try service(secrets: secrets)
        defer { clean(defaults) }
        try await ingest("the real history")
        _ = try await onDisk.enable(passphrase: nil, folder: folder, includeSensitive: false, iterations: 1000)
        onDisk.stop()
        let before = try Data(contentsOf: backupFile)

        let (inMemory, _) = try service(secrets: secrets, isPersistentStore: false)
        let outcome = await inMemory.backUpNow()

        #expect(outcome == .refused(.storeNotOnDisk))
        #expect(try Data(contentsOf: backupFile) == before)
        #expect(!FileManager.default.fileExists(atPath: previousFile.path))
    }

    @Test("the backup it replaces is kept as the previous generation")
    func whenBackedUpAgain_thenThePreviousFileIsKept() async throws {
        let secrets = MemorySecrets()
        let (service, defaults) = try service(secrets: secrets)
        defer { clean(defaults) }
        try await ingest("first clip")
        _ = try await service.enable(passphrase: nil, folder: folder, includeSensitive: false, iterations: 1000)
        let key = try #require(try BackupKeyStore(secrets: secrets).existingKey())
        try await ingest("second clip")

        _ = await service.backUpNow()

        #expect(try clipCount(in: backupFile, key: key) == 2)
        #expect(try clipCount(in: previousFile, key: key) == 1)
        service.stop()
    }

    @Test("a history far smaller than the last backup is refused unless the person confirms")
    func whenHistoryShrinks_thenOnlyAConfirmedBackupReplacesTheFile() async throws {
        let secrets = MemorySecrets()
        let (service, defaults) = try service(secrets: secrets)
        defer { clean(defaults) }
        for index in 0..<12 {
            try await ingest("clip number \(index) about basil")
        }
        _ = try await service.enable(passphrase: nil, folder: folder, includeSensitive: false, iterations: 1000)
        let key = try #require(try BackupKeyStore(secrets: secrets).existingKey())
        let context = ModelContext(container)
        for item in try context.fetch(FetchDescriptor<ClipboardItem>()).dropFirst(2) {
            context.delete(item)
        }
        try context.save()

        #expect(await service.backUpNow() == .refused(.muchSmaller(now: 2, before: 12)))
        #expect(try clipCount(in: backupFile, key: key) == 12)

        guard case .written = await service.backUpNow(allowShrink: true) else {
            Issue.record("a confirmed backup was not written")
            return
        }
        #expect(try clipCount(in: backupFile, key: key) == 2)
        service.stop()
    }

    @Test("setting up again in a folder that holds a backup this Mac has no key for is stopped before it overwrites")
    func whenFolderHoldsABackupAndNoKeyExists_thenSetUpStops() async throws {
        let (first, defaults) = try service()
        defer { clean(defaults) }
        try await ingest("an old clip")
        _ = try await first.enable(passphrase: nil, folder: folder, includeSensitive: false, iterations: 1000)
        first.stop()
        let before = try Data(contentsOf: backupFile)

        let (second, _) = try service(secrets: MemorySecrets())
        await #expect(throws: AutoBackupError.backupAlreadyInFolder) {
            try await second.enable(passphrase: nil, folder: folder, includeSensitive: false, iterations: 1000)
        }
        #expect(try Data(contentsOf: backupFile) == before)
    }

    @Test("a file under the old name with this Mac's key is adopted on re-enable and deduplicated")
    func whenOldNamedFileIsOurs_thenItIsAdoptedAndNeverDuplicated() async throws {
        let secrets = MemorySecrets()
        let (service, defaults) = try service(secrets: secrets)
        defer { clean(defaults) }
        try await ingest("first clip")
        _ = try await service.enable(passphrase: nil, folder: folder, includeSensitive: false, iterations: 1000)
        let legacy = folder.appendingPathComponent(AutoBackupSettings.legacyFileName(forMac: "Test Mac"))
        try FileManager.default.moveItem(at: backupFile, to: legacy)
        try await ingest("second clip")
        _ = try await service.enable(passphrase: nil, folder: folder, includeSensitive: false, iterations: 1000)
        let key = try #require(try BackupKeyStore(secrets: secrets).existingKey())
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(try clipCount(in: backupFile, key: key) == 2)
        #expect(try clipCount(in: previousFile, key: key) == 1)
        try FileManager.default.copyItem(at: backupFile, to: legacy)
        try await ingest("third clip")
        _ = await service.backUpNow()
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(try clipCount(in: backupFile, key: key) == 3)
        service.stop()
    }

    @Test("keeping the backup after Clear Everything pauses automatic backup until Back Up Now is confirmed")
    func whenClearedAndBackupKept_thenTheOldFileSurvives() async throws {
        let secrets = MemorySecrets()
        let (service, defaults) = try service(secrets: secrets)
        defer { clean(defaults) }
        try await ingest("a clip worth keeping")
        _ = try await service.enable(passphrase: nil, folder: folder, includeSensitive: false, iterations: 1000)
        let key = try #require(try BackupKeyStore(secrets: secrets).existingKey())
        let context = ModelContext(container)
        for item in try context.fetch(FetchDescriptor<ClipboardItem>()) {
            context.delete(item)
        }
        try context.save()

        service.afterClearEverything(deleteBackup: false)

        #expect(await service.backUpNow() == .refused(.keptAfterClear))
        #expect(try clipCount(in: backupFile, key: key) == 1)
        guard case .written = await service.backUpNow(allowShrink: true) else {
            Issue.record("a confirmed backup was not written")
            return
        }
        #expect(try clipCount(in: backupFile, key: key) == 0)
        #expect(await service.backUpNow() != .refused(.keptAfterClear), "the pause ends once confirmed")
    }
}

extension AutoBackupServiceTests {
    @Test("deleting the backup with Clear Everything removes the file and its previous copy")
    func whenClearedAndBackupDeleted_thenTheFilesAreGone() async throws {
        let (service, defaults) = try service()
        defer { clean(defaults) }
        try await ingest("first")
        _ = try await service.enable(passphrase: nil, folder: folder, includeSensitive: false, iterations: 1000)
        try await ingest("second")
        _ = await service.backUpNow()
        #expect(FileManager.default.fileExists(atPath: previousFile.path))

        service.afterClearEverything(deleteBackup: true)

        #expect(!FileManager.default.fileExists(atPath: backupFile.path))
        #expect(!FileManager.default.fileExists(atPath: previousFile.path))
    }

    @Test("a file in the folder that this Mac's key does not open is left alone")
    func whenTheFileIsUnderAnotherKey_thenItIsNotReplaced() async throws {
        let (service, defaults) = try service()
        defer { clean(defaults) }
        try await ingest("remember the basil")
        _ = try await service.enable(
            passphrase: "correct horse battery staple", folder: folder, includeSensitive: false, iterations: 1000
        )
        let foreignKey = BackupKey.generate()
        let foreignHeader = try BackupFile.makeHeader(key: foreignKey, passphrase: "other", iterations: 1000)
        let foreign = try BackupFile.write(
            records: [], origin: BackupOrigin(sequence: 1, deviceID: "mac-b", createdAt: .now),
            key: foreignKey, header: foreignHeader
        )
        try foreign.write(to: backupFile, options: .atomic)
        try await ingest("a later clip")

        let outcome = await service.backUpNow()

        #expect(outcome == .refused(.anotherKeyInFolder))
        #expect(try Data(contentsOf: backupFile) == foreign, "the other backup must be untouched")
    }
}
