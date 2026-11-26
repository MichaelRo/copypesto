// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("A backup written by hand", .serialized)
struct ManualBackupWriterTests {
    private let source: ModelContainer
    private let folder: URL
    private let passphrase = "correct horse battery staple"
    private let origin = BackupOrigin(
        sequence: 3,
        deviceID: "phone-a",
        createdAt: Date(timeIntervalSince1970: 1_800_000_000)
    )

    init() throws {
        source = try ModelContainerSetup.makeInMemory()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("manual-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func ingest(_ text: String) async throws {
        let payload = Data(text.utf8)
        try await StorageService(modelContainer: source).ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: payload, payloadString: text,
            frontmostBundleID: "com.apple.mobilenotes", timestamp: .now,
            contentHash: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        ))
    }

    private func write(
        key: BackupKey, header: Data? = nil, storeIsOnDisk: Bool = true, includeSensitive: Bool = false
    ) async throws
    -> (url: URL, result: ManualBackupWriter.Result) {
        let header = try header ?? BackupFile.makeHeader(key: key, passphrase: passphrase, iterations: 1000)
        let url = folder.appendingPathComponent("Pesto Backup.pestobackup")
        let result = try await ManualBackupWriter(container: source, storeIsOnDisk: storeIsOnDisk).write(
            to: url, key: key, header: header, includeSensitive: includeSensitive, origin: origin
        )
        return (url, result)
    }

    private func leftovers() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    @Test("the file opens with the passphrase and with the recovery key, and restores the clips")
    func whenWritten_thenBothCredentialsOpenItAndItRestores() async throws {
        try await ingest("ship on friday")
        try await ingest("a second clip")
        let key = BackupKey.generate()

        let (url, result) = try await write(key: key)

        #expect(result.summary.items == 2)
        #expect(try result.bytes == (FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int))
        let byPassphrase = try BackupFile.verify(url: url, credential: .passphrase(passphrase))
        #expect(byPassphrase.itemCount == 2)
        #expect(byPassphrase.manifest.sequence == 3)
        #expect(byPassphrase.manifest.deviceID == "phone-a")
        let byKey = try BackupFile.verify(url: url, credential: .recoveryKey(BackupKey(recoveryKey: key.recoveryKey)))
        let target = try ModelContainerSetup.makeInMemory()
        let summary = try await StorageService(modelContainer: target).restore(byKey)
        #expect(summary.restored == 2)
        #expect(try leftovers() == ["Pesto Backup.pestobackup"], "no partial file is left beside it")
    }

    @Test("a secret is left out unless the person includes hidden clips")
    func whenSecretAndNotIncluded_thenLeftOut() async throws {
        try await ingest("sk-live-4eC39HqLyjWDarjtT1zdp7dc")
        try await ingest("an ordinary clip")

        let left = try await write(key: .generate()).result.summary
        #expect(left.items == 1)
        #expect(left.skippedSensitive == 1)

        let kept = try await write(key: .generate(), includeSensitive: true).result.summary
        #expect(kept.items == 2)
    }

    @Test("a history only in memory is refused and writes nothing")
    func whenStoreNotOnDisk_thenRefusedAndNothingWritten() async throws {
        try await ingest("a clip")

        await #expect(throws: ManualBackupError.storeNotOnDisk) {
            try await write(key: .generate(), storeIsOnDisk: false)
        }
        #expect(try leftovers().isEmpty)
    }

    @Test("a header made for another key is refused and leaves no file")
    func whenHeaderOfAnotherKey_thenRefusedAndNothingLeft() async throws {
        try await ingest("a clip")
        let other = try BackupFile.makeHeader(key: .generate(), passphrase: passphrase, iterations: 1000)

        await #expect(throws: BackupError.wrongCredential) {
            try await write(key: .generate(), header: other)
        }
        #expect(try leftovers().isEmpty)
    }

    @Test("a folder where the file would go is left alone, and no partial file stays beside it")
    func whenTheTargetCannotBeReplaced_thenNoPartialLeft() async throws {
        try await ingest("a clip")
        let blocker = folder.appendingPathComponent("Pesto Backup.pestobackup", isDirectory: true)
        try FileManager.default.createDirectory(
            at: blocker.appendingPathComponent("inside"), withIntermediateDirectories: true
        )

        await #expect(throws: (any Error).self) { try await write(key: .generate()) }
        #expect(try leftovers() == ["Pesto Backup.pestobackup"], "only what was there before")
        #expect(FileManager.default.fileExists(atPath: blocker.appendingPathComponent("inside").path))
    }

    @Test("a second backup to the same name replaces the first")
    func whenWrittenTwice_thenReplaced() async throws {
        try await ingest("first")
        let key = BackupKey.generate()
        _ = try await write(key: key)
        try await ingest("second")

        let (url, _) = try await write(key: key)

        #expect(try BackupFile.verify(url: url, credential: .recoveryKey(key)).itemCount == 2)
        #expect(try leftovers() == ["Pesto Backup.pestobackup"])
    }

    @Test("an export name carries the device, its id and the minute, and cannot leave the folder")
    func exportFileName_isNamedAndSafe() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let utc = TimeZone(identifier: "UTC") ?? .current
        let name = AutoBackupSettings.exportFileName(
            device: "iPhone", deviceID: "3F2A9C41-0000-4000-8000-000000000001", date: date, timeZone: utc
        )
        #expect(name == "Pesto Backup \u{2013} iPhone (3F2A9C41) 2027-01-15 08.00.pestobackup")
        #expect(!AutoBackupSettings.exportFileName(device: "../x/y", deviceID: "../z", date: date).contains("/"))
    }
}
