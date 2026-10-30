// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

extension AutoBackupServiceTests {
    private func otherFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-autobackup-other-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fileName() -> String {
        AutoBackupSettings.fileName(forMac: "Test Mac", deviceID: "mac-a")
    }

    @Test("changing the folder writes the backup there and remembers it, and the old file stays where it was")
    func whenTheFolderIsChanged_thenTheBackupIsWrittenThere() async throws {
        let (service, defaults) = try service()
        defer { clean(defaults) }
        try await ingest("remember the basil")
        _ = try await service.enable(passphrase: nil, folder: folder, includeSensitive: false, iterations: 1000)
        let destination = try otherFolder()
        defer { try? FileManager.default.removeItem(at: destination) }

        let outcome = await service.changeFolder(to: destination)

        guard case .written = outcome else {
            Issue.record("expected a written backup, got \(outcome)")
            return
        }
        #expect(AutoBackupSettings(defaults: defaults).folder == destination)
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent(fileName()).path))
        #expect(FileManager.default.fileExists(atPath: backupFile.path), "the old file is the person's to delete")
        service.stop()
    }

    @Test("a folder that does not exist is refused and the old one is kept")
    func whenTheFolderIsMissing_thenTheOldFolderIsKept() async throws {
        let (service, defaults) = try service()
        defer { clean(defaults) }
        try await ingest("remember the basil")
        _ = try await service.enable(passphrase: nil, folder: folder, includeSensitive: false, iterations: 1000)
        let missing = folder.appendingPathComponent("not-here")

        let outcome = await service.changeFolder(to: missing)

        #expect(outcome == .folderUnavailable)
        #expect(AutoBackupSettings(defaults: defaults).folder == folder)
        #expect(AutoBackupSettings(defaults: defaults).problem == nil, "the old folder still works")
        service.stop()
    }

    @Test("a folder that holds a backup this Mac's key does not open is refused, untouched, and the old folder is kept")
    func whenTheNewFolderHoldsAnotherKeysBackup_thenItIsLeftAlone() async throws {
        let (service, defaults) = try service()
        defer { clean(defaults) }
        try await ingest("remember the basil")
        _ = try await service.enable(passphrase: nil, folder: folder, includeSensitive: false, iterations: 1000)
        let destination = try otherFolder()
        defer { try? FileManager.default.removeItem(at: destination) }
        let foreignKey = BackupKey.generate()
        let foreignHeader = try BackupFile.makeHeader(key: foreignKey, passphrase: "other", iterations: 1000)
        let foreign = try BackupFile.write(
            records: [], origin: BackupOrigin(sequence: 1, deviceID: "mac-b", createdAt: .now),
            key: foreignKey, header: foreignHeader
        )
        let target = destination.appendingPathComponent(fileName())
        try foreign.write(to: target, options: .atomic)

        let outcome = await service.changeFolder(to: destination)

        #expect(outcome == .refused(.anotherKeyInFolder))
        #expect(try Data(contentsOf: target) == foreign)
        #expect(AutoBackupSettings(defaults: defaults).folder == folder)
        service.stop()
    }

    @Test("with no backup set up there is nothing to move")
    func whenNoBackupIsSetUp_thenNothingChanges() async throws {
        let (service, defaults) = try service()
        defer { clean(defaults) }

        let outcome = await service.changeFolder(to: folder)

        #expect(outcome == .needsSetup)
        #expect(AutoBackupSettings(defaults: defaults).folder == nil)
        service.stop()
    }
}
