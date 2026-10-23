// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("Backup coordinator", .serialized)
@MainActor
struct BackupCoordinatorTests {
    private let source: ModelContainer
    private let target: ModelContainer
    private let defaultsName = UUID().uuidString
    private let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("test-\(UUID().uuidString).pestobackup")

    init() throws {
        source = try ModelContainerSetup.makeInMemory().synced
        target = try ModelContainerSetup.makeInMemory().synced
    }

    private func coordinator(_ container: ModelContainer, device: String = "mac-a") -> BackupCoordinator {
        BackupCoordinator(
            container: container, defaults: ThrowawayDefaults.make(defaultsName), deviceID: { device }
        )
    }

    /// A backup made the way the app makes one: by the backup service, with this Mac's sequence kept in the same
    /// preferences as the coordinator reads.
    private func makeBackup(
        from container: ModelContainer,
        passphrase: String?,
        secrets: MemorySecrets = MemorySecrets(),
        to url: URL
    ) async throws
    -> String? {
        let folder = url.deletingLastPathComponent().appendingPathComponent("backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = ThrowawayDefaults.make(defaultsName)
        let service = AutoBackupService(
            container: container, settings: AutoBackupSettings(defaults: defaults),
            keyStore: BackupKeyStore(secrets: secrets), defaults: defaults, deviceID: { "mac-a" },
            macName: { "Test Mac" }
        )
        let result = try await service.enable(
            passphrase: passphrase, folder: folder, includeSensitive: false, automatic: false, iterations: 1000
        )
        service.stop()
        let written = folder.appendingPathComponent(AutoBackupSettings.fileName(forMac: "Test Mac", deviceID: "mac-a"))
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.copyItem(at: written, to: url)
        return result.recoveryKey
    }

    private func fill(_ container: ModelContainer) async throws {
        let service = StorageService(modelContainer: container)
        let payload = Data("remember the basil".utf8)
        try await service.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: payload, payloadString: "remember the basil",
            frontmostBundleID: "com.apple.Notes", timestamp: .now,
            contentHash: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        ))
    }

    @Test("a backup opens with its passphrase or its recovery key, and restores into another history")
    func whenOpened_thenRestoresIntoAnotherMac() async throws {
        try await fill(source)
        defer { try? FileManager.default.removeItem(at: file) }
        let recovery = try #require(try await makeBackup(
            from: source, passphrase: "correct horse battery staple", to: file
        ))
        let receiving = coordinator(target, device: "mac-b")

        let viaPassphrase = try await receiving.open(file, credential: .passphrase("correct horse battery staple"))
        let viaRecovery = try await receiving.open(file, credential: .recoveryKey(BackupKey(recoveryKey: recovery)))
        let summary = try await receiving.restore(viaPassphrase)

        #expect(viaPassphrase.backup.manifest == viaRecovery.backup.manifest)
        #expect(viaPassphrase.itemCount == 1 && viaPassphrase.collectionCount == 0 && viaPassphrase.deletionCount == 0)
        #expect(viaPassphrase.createdAt == viaPassphrase.backup.manifest.createdAt)
        #expect(viaPassphrase.warning == nil)
        #expect(summary.restored == 1)
        #expect(try ModelContext(target).fetch(FetchDescriptor<ClipboardItem>()).first?
            .displayPreviewText == "remember the basil")
    }

    @Test("a wrong passphrase is refused and nothing is read")
    func whenWrongPassphrase_thenRefused() async throws {
        try await fill(source)
        defer { try? FileManager.default.removeItem(at: file) }
        _ = try await makeBackup(from: source, passphrase: "correct horse battery staple", to: file)

        await #expect(throws: BackupError.wrongCredential) {
            _ = try await coordinator(target).open(file, credential: .passphrase("not the passphrase"))
        }
    }

    @Test("restoring a backup older than this Mac's latest one is flagged before anything is mixed in")
    func whenOlderBackup_thenWarned() async throws {
        try await fill(source)
        let secrets = MemorySecrets()
        defer { try? FileManager.default.removeItem(at: file) }
        let older = file.deletingLastPathComponent().appendingPathComponent("older-\(UUID().uuidString).pestobackup")
        defer { try? FileManager.default.removeItem(at: older) }
        _ = try await makeBackup(from: source, passphrase: "correct horse battery staple", secrets: secrets, to: older)
        _ = try await makeBackup(from: source, passphrase: "correct horse battery staple", secrets: secrets, to: file)

        let preview = try await coordinator(source).open(
            older, credential: .passphrase("correct horse battery staple")
        )

        #expect(preview.warning == .olderThanThisMac)
    }

    @Test("restoring in place of unreadable history discards it first, then restores, in that order")
    func whenReplacing_thenDiscardThenRestore() async throws {
        try await fill(source)
        try await fill(target)
        defer { try? FileManager.default.removeItem(at: file) }
        _ = try await makeBackup(from: source, passphrase: "correct horse battery staple", to: file)
        let receiving = coordinator(target, device: "mac-b")
        let preview = try await receiving.open(file, credential: .passphrase("correct horse battery staple"))
        let context = ModelContext(target)
        #expect(try context.fetchCount(FetchDescriptor<ClipboardItem>()) == 1)
        var steps: [String] = []

        let summary = try await receiving.restore(preview, replacing: {
            steps.append("discard")
            try UnreadableHistory.discard(in: context)
            try steps.append("discarded: \(context.fetchCount(FetchDescriptor<ClipboardItem>())) clips left")
        })

        #expect(steps == ["discard", "discarded: 0 clips left"])
        #expect(
            summary.restored == 1,
            "the clip was already here before the discard, so it only comes back if the discard ran first"
        )
        #expect(try ModelContext(target).fetchCount(FetchDescriptor<ClipboardItem>()) == 1)
    }

    @Test("a discard that fails restores nothing and says why")
    func whenDiscardFails_thenNothingRestored() async throws {
        try await fill(source)
        defer { try? FileManager.default.removeItem(at: file) }
        _ = try await makeBackup(from: source, passphrase: "correct horse battery staple", to: file)
        let receiving = coordinator(target, device: "mac-b")
        let preview = try await receiving.open(file, credential: .passphrase("correct horse battery staple"))
        struct Refused: Error {}

        await #expect(throws: Refused.self) {
            _ = try await receiving.restore(preview, replacing: { throw Refused() })
        }

        #expect(try ModelContext(target).fetchCount(FetchDescriptor<ClipboardItem>()) == 0)
    }

    @Test("a backup that does not open never reaches the discard")
    func whenWrongPassphrase_thenNothingDiscarded() async throws {
        try await fill(source)
        try await fill(target)
        defer { try? FileManager.default.removeItem(at: file) }
        _ = try await makeBackup(from: source, passphrase: "correct horse battery staple", to: file)

        await #expect(throws: BackupError.wrongCredential) {
            _ = try await coordinator(target).open(file, credential: .passphrase("wrong"))
        }

        #expect(try ModelContext(target).fetchCount(FetchDescriptor<ClipboardItem>()) == 1)
    }

    @Test("discarding unreadable history empties clips and blobs but keeps collections")
    func whenDiscard_thenClipsGoCollectionsStay() async throws {
        try await fill(target)
        let context = ModelContext(target)
        context.insert(Pinboard(name: "Work", symbolName: "folder", colorHex: "#888888", sortOrder: 0))
        try context.save()

        try UnreadableHistory.discard(in: context)

        #expect(try context.fetchCount(FetchDescriptor<ClipboardItem>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ClipboardBlob>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Pinboard>()) == 1)
    }
}
