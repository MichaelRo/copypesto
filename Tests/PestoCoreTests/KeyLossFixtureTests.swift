// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The backup a UI test restores after a lost key")
struct KeyLossFixtureTests {
    private func written() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pestobackup")
        try KeyLossFixture.write(to: url)
        return url
    }

    @Test("it opens with the fixture passphrase and holds one clip")
    func whenWritten_thenOpensWithItsPassphrase() throws {
        let url = try written()
        defer { try? FileManager.default.removeItem(at: url) }

        let backup = try BackupFile.verify(url: url, credential: .passphrase(KeyLossFixture.passphrase))

        #expect(backup.itemCount == 1)
    }

    @Test("a wrong passphrase is refused")
    func whenWrongPassphrase_thenRefused() throws {
        let url = try written()
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: BackupError.wrongCredential) {
            _ = try BackupFile.verify(url: url, credential: .passphrase("not it"))
        }
    }
}
