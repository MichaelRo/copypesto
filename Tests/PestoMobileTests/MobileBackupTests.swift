// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("iOS backup and restore by hand", .serialized)
@MainActor
struct MobileBackupTests {
    private let passphrase = "basil garlic pine nuts parmesan"

    private func backUp(
        _ library: MobileTestLibrary, protection: AutoBackupSettings.Protection = .passphrase,
        includeHidden: Bool = false
    ) async throws
    -> MobileBackupFile {
        try #require(await library.state.backUp(
            protection: protection, passphrase: passphrase, includeHidden: includeHidden, iterations: 1000
        ))
    }

    @Test("a backup opens with its passphrase and restores its clips on another device")
    func whenBackedUpAndRestoredElsewhere_thenClipsComeBack() async throws {
        let source = try await MobileTestLibrary()
        try await source.add("Ship on Friday")
        try await source.add("https://copypesto.net")
        let file = try await backUp(source)
        defer { source.state.backupNotSaved(file) }
        #expect(file.url.pathExtension == BackupFileType.fileExtension)
        #expect(ShareFile.owns(file.url), "the file waits in the folder the lock and a clear empty")
        #expect(file.summary.items == 2)

        let destination = try await MobileTestLibrary()
        let preview = try await destination.state.openBackup(at: file.url, credential: .passphrase(passphrase))
        #expect(preview.itemCount == 2)
        let counts = try #require(await destination.state.restorePreview(preview))
        #expect(counts.wouldAdd == 2)
        let summary = try #require(await destination.state.restoreBackup(preview))
        try await destination.refreshed()

        #expect(summary.restored == 2)
        #expect(Set(destination.store.items.map(\.displayPreviewText)) == ["Ship on Friday", "https://copypesto.net"])

        let again = try await destination.state.openBackup(at: file.url, credential: .passphrase(passphrase))
        let second = try #require(await destination.state.restoreBackup(again))
        #expect(second.restored == 0)
        #expect(second.alreadyHad == 2, "restoring twice changes nothing")
    }

    @Test("the recovery key is shown when the key is new, and every time for a recovery-key-only backup")
    func whenBackedUpAgain_thenRecoveryKeyShownOnlyWhenNeeded() async throws {
        let library = try await MobileTestLibrary()
        try await library.add("A clip")
        #expect(!library.state.hasBackupKey)

        let first = try await backUp(library)
        defer { library.state.backupNotSaved(first) }
        let key = try #require(first.recoveryKey)
        #expect(library.state.hasBackupKey)

        let second = try await backUp(library)
        defer { library.state.backupNotSaved(second) }
        #expect(second.recoveryKey == nil, "the same key, already shown")

        let keyOnly = try await backUp(library, protection: .recoveryKey)
        defer { library.state.backupNotSaved(keyOnly) }
        #expect(keyOnly.recoveryKey == key, "only the recovery key opens it, so it is shown again")
        let opened = try await library.state.openBackup(
            at: keyOnly.url, credential: .recoveryKey(BackupKey(recoveryKey: key))
        )
        #expect(opened.itemCount == 1)
        await #expect(throws: BackupError.wrongCredential) {
            _ = try await library.state.openBackup(at: keyOnly.url, credential: .passphrase(passphrase))
        }
    }

    @Test("an existing recovery key is not shown by a recovery-key-only backup without a fresh Face ID")
    func whenRecoveryKeyOnlyAndAuthenticationRefused_thenNoBackupAndNoKey() async throws {
        let library = try await MobileTestLibrary(lock: MobileHistoryLock(
            authenticator: StubUserAuthenticator(available: true, grants: false), grace: AuthenticationGrace(),
            isEnabled: { false }
        ))
        try await library.add("A clip")
        let first = try await backUp(library)
        defer { library.state.backupNotSaved(first) }
        #expect(first.recoveryKey != nil, "a new key is shown once, as on the Mac")

        let keyOnly = await library.state.backUp(
            protection: .recoveryKey, passphrase: "", includeHidden: false, iterations: 1000
        )

        #expect(keyOnly == nil)
        #expect(await library.state.revealBackupRecoveryKey() == nil)
    }

    @Test("a wrong passphrase does not open the file and says so")
    func whenWrongPassphrase_thenRefused() async throws {
        let library = try await MobileTestLibrary()
        try await library.add("A clip")
        let file = try await backUp(library)
        defer { library.state.backupNotSaved(file) }

        do {
            _ = try await library.state.openBackup(at: file.url, credential: .passphrase("not the passphrase at all"))
            Issue.record("a wrong passphrase opened the backup")
        } catch {
            #expect(error as? BackupError == .wrongCredential)
            #expect(BackupText.openFailure(error) == BackupText.openFailure(BackupError.wrongCredential))
        }
    }

    @Test("a passphrase too easy to guess writes nothing")
    func whenWeakPassphrase_thenNoBackup() async throws {
        let library = try await MobileTestLibrary()
        try await library.add("A clip")

        let file = await library.state.backUp(
            protection: .passphrase, passphrase: "password1234", includeHidden: false, iterations: 1000
        )

        #expect(file == nil)
        #expect(!library.state.hasBackupKey, "no key is made for a backup that is not written")
    }

    @Test("a secret stays out unless the person includes it")
    func whenSecret_thenLeftOutUnlessIncluded() async throws {
        let library = try await MobileTestLibrary()
        try await library.service.ingest(#require(ClipCapture.text("sk-live-4eC39HqLyjWDarjtT1zdp7dc")))
        try await library.add("An ordinary clip")

        let without = try await backUp(library)
        defer { library.state.backupNotSaved(without) }
        #expect(without.summary.items == 1)
        #expect(without.summary.skippedSensitive == 1)

        let with = try await backUp(library, includeHidden: true)
        defer { library.state.backupNotSaved(with) }
        #expect(with.summary.items == 2)
    }

    @Test("saving moves this device's sequence on and removes the temporary file; cancelling only removes it")
    func whenSavedOrCancelled_thenTemporaryFileGoes() async throws {
        let defaults = AppDefaults.store
        let sequenceBefore = defaults.object(forKey: BackupCoordinator.sequenceKey)
        defer {
            defaults.set(sequenceBefore, forKey: BackupCoordinator.sequenceKey)
            defaults.removeValue(for: Setting.lastManualBackup)
        }
        defaults.set(0, forKey: BackupCoordinator.sequenceKey)
        let library = try await MobileTestLibrary()
        try await library.add("A clip")

        let cancelled = try await backUp(library)
        library.state.backupNotSaved(cancelled)
        #expect(!FileManager.default.fileExists(atPath: cancelled.url.path))
        #expect(defaults.integer(forKey: BackupCoordinator.sequenceKey) == 0)

        let saved = try await backUp(library)
        library.state.backupSaved(saved)
        #expect(!FileManager.default.fileExists(atPath: saved.url.path))
        #expect(defaults.integer(forKey: BackupCoordinator.sequenceKey) == 1)
        #expect(defaults.value(for: Setting.lastManualBackup) > .distantPast)
        #expect(library.state.notice?.isProblem == false)
    }
}
