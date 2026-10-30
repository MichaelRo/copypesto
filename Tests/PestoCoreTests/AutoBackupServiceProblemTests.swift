// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

extension AutoBackupServiceTests {
    @Test("a refused backup leaves a problem the Settings pane can show without opening the Keychain")
    func whenARefusalHappens_thenTheProblemIsStored() async throws {
        let (service, defaults) = try service(isPersistentStore: false)
        defer { clean(defaults) }
        try await ingest("clip")
        _ = try await service.enable(passphrase: nil, folder: folder, includeSensitive: false, iterations: 1000)

        let outcome = await service.backUpNow()

        #expect(outcome == .refused(.storeNotOnDisk))
        #expect(AutoBackupSettings(defaults: defaults).problem == .refused)
        service.stop()
    }

    @Test("a missing folder is stored as a problem of its own")
    func whenTheFolderIsGone_thenFolderMissingIsStored() async throws {
        let (service, defaults) = try service()
        defer { clean(defaults) }
        try await ingest("clip")
        _ = try await service.enable(passphrase: nil, folder: folder, includeSensitive: false, iterations: 1000)
        try FileManager.default.removeItem(at: folder)

        let outcome = await service.backUpNow()

        #expect(outcome == .folderUnavailable)
        #expect(AutoBackupSettings(defaults: defaults).problem == .folderMissing)
        service.stop()
    }

    @Test("a backup that is written afterwards clears the problem")
    func whenABackupSucceeds_thenTheProblemIsCleared() async throws {
        let (service, defaults) = try service()
        defer { clean(defaults) }
        try await ingest("clip")
        _ = try await service.enable(passphrase: nil, folder: folder, includeSensitive: false, iterations: 1000)
        AutoBackupSettings(defaults: defaults).problem = .failed

        guard case .written = await service.backUpNow() else {
            Issue.record("the backup was not written")
            return
        }

        #expect(AutoBackupSettings(defaults: defaults).problem == nil)
        service.stop()
    }
}
