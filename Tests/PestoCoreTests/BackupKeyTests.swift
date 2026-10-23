// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import Testing
@testable import PestoCore

@Suite("Backup key")
struct BackupKeyTests {
    @Test("PBKDF2-HMAC-SHA256 matches the published test vector")
    func whenDerived_thenMatchesKnownAnswer() throws {
        let key = try #require(BackupKeyDerivation.pbkdf2SHA256(
            passphrase: "password",
            salt: Data("salt".utf8),
            iterations: 1
        ))
        let hex = key.withUnsafeBytes { Data($0) }.map { String(format: "%02x", $0) }.joined()
        #expect(hex == "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
    }

    @Test("the default cost is at least the OWASP figure for PBKDF2-HMAC-SHA256")
    func whenDefault_thenAtLeast600k() {
        #expect(BackupKeyDerivation.defaultIterations >= 600_000)
    }

    @Test("a recovery key round-trips and is written in groups of four")
    func whenRecoveryKeyShown_thenRestoresTheSameKey() throws {
        let key = BackupKey.generate()
        let text = key.recoveryKey
        let groups = text.split(separator: "-")
        #expect(groups.dropLast().allSatisfy { $0.count == 4 } && (1...4).contains(groups.last?.count ?? 0))
        #expect(try BackupKey(recoveryKey: text) == key)
    }

    @Test("case, spaces and missing dashes are forgiven")
    func whenTypedLoosely_thenStillParses() throws {
        let key = BackupKey.generate()
        let loose = key.recoveryKey.lowercased().replacingOccurrences(of: "-", with: " ")
        #expect(try BackupKey(recoveryKey: loose) == key)
    }

    @Test("a single mistyped character is rejected before any decryption")
    func whenOneCharacterChanges_thenMalformed() throws {
        let text = BackupKey.generate().recoveryKey
        var characters = Array(text)
        let index = try #require(characters.firstIndex { $0 != "-" })
        characters[index] = characters[index] == "A" ? "B" : "A"
        #expect(throws: BackupError.malformedRecoveryKey) { try BackupKey(recoveryKey: String(characters)) }
    }

    @Test("wrong length and foreign characters are rejected")
    func whenNotAKey_thenMalformed() {
        for bad in ["", "ABCD-EFGH", "1111-1111-1111", String(repeating: "A", count: 200)] {
            #expect(throws: BackupError.malformedRecoveryKey) { try BackupKey(recoveryKey: bad) }
        }
    }

    @Test("two generated keys differ")
    func whenGeneratedTwice_thenDifferent() {
        #expect(BackupKey.generate() != BackupKey.generate())
    }
}
