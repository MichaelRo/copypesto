// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

/// Holds an item that `read` cannot see (a duplicate that exists but is unreadable or the wrong shape), the way a
/// second process or a damaged Keychain item behaves.
private final class StubbornSecrets: SecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    private let hiddenFirstRead: Data?
    private var reads = 0

    init(hiddenFirstRead: Data?) {
        self.hiddenFirstRead = hiddenFirstRead
    }

    func read(service: String, account: String) throws -> Data? {
        lock.withLock {
            reads += 1
            if reads == 1 { return nil }
            return items["\(service)|\(account)"] ?? hiddenFirstRead
        }
    }

    func write(_ data: Data, service: String, account: String) throws {
        lock.withLock {
            let key = "\(service)|\(account)"
            if items[key] == nil, hiddenFirstRead == nil { items[key] = data }
        }
    }

    func delete(service _: String, account _: String) {}
}

@Suite("Backup key store races")
struct BackupKeyStoreRaceTests {
    @Test("a key stored by someone else between the read and the write is the one used and shown")
    func whenAnotherKeyAppearsBeforeTheWrite_thenItIsAdopted() throws {
        let other = BackupKey.generate()
        let store = BackupKeyStore(secrets: StubbornSecrets(hiddenFirstRead: other.bytes))

        let result = try store.keyCreatingIfNeeded()

        #expect(result.key.bytes == other.bytes)
        #expect(!result.isNew, "the recovery key must be the stored key, not the one that lost the race")
    }

    @Test("an unusable item in the way is an error instead of a key that was never stored")
    func whenAnUnusableItemBlocksTheWrite_thenItThrows() {
        let store = BackupKeyStore(secrets: StubbornSecrets(hiddenFirstRead: Data([1, 2, 3])))

        #expect(throws: (any Error).self) { try store.keyCreatingIfNeeded() }
    }
}

@Suite("Passphrase strength")
struct PassphraseStrengthTests {
    @Test("short or common passphrases are too weak to accept")
    func whenShortOrCommon_thenWeak() {
        #expect(PassphraseStrength.evaluate("") == .tooShort)
        #expect(PassphraseStrength.evaluate("abc123") == .tooShort)
        #expect(PassphraseStrength.evaluate("password1234") == .weak)
        #expect(PassphraseStrength.evaluate("aaaaaaaaaaaa") == .weak)
    }

    @Test("a long mixed passphrase, or several words, is good")
    func whenLongOrManyWords_thenGood() {
        #expect(PassphraseStrength.evaluate("correct horse battery staple") == .strong)
        #expect(PassphraseStrength.evaluate("Tq7!mWz2#Lp9vXr4") == .strong)
        #expect(PassphraseStrength.evaluate("basil garden twelve") == .fair)
    }

    @Test("only fair and strong are accepted")
    func whenChecked_thenAcceptance() {
        #expect(!PassphraseStrength.tooShort.isAcceptable)
        #expect(!PassphraseStrength.weak.isAcceptable)
        #expect(PassphraseStrength.fair.isAcceptable)
        #expect(PassphraseStrength.strong.isAcceptable)
    }
}

@Suite("Backup key storage")
struct BackupKeyStoreTests {
    @Test("the first backup creates the key once and later backups reuse it")
    func whenAsked_thenSameKeyEveryTime() throws {
        let store = BackupKeyStore(secrets: MemorySecrets())

        let first = try store.keyCreatingIfNeeded()
        let second = try store.keyCreatingIfNeeded()

        #expect(first.isNew && !second.isNew)
        #expect(first.key == second.key)
    }

    @Test("the key can be read back, and forgotten")
    func whenStoredThenCleared_thenGone() throws {
        let store = BackupKeyStore(secrets: MemorySecrets())
        let made = try store.keyCreatingIfNeeded()

        #expect(try store.existingKey() == made.key)
        store.forget()
        #expect(try store.existingKey() == nil)
    }
}

@Suite("Restore warnings")
struct RestoreWarningTests {
    private func manifest(sequence: UInt64, device: String) -> BackupManifest {
        BackupManifest(recordCount: 1, sequence: sequence, deviceID: device, createdAt: Date())
    }

    @Test("a backup older than the last one made on this Mac is flagged")
    func whenOlderThanLocalState_thenWarn() {
        #expect(
            RestoreWarning.evaluate(
                manifest: manifest(sequence: 2, device: "mine"),
                lastLocalSequence: 5,
                localDeviceID: "mine"
            )
                == .olderThanThisMac
        )
    }

    @Test("the newest backup, one from another Mac, and a first restore are not flagged")
    func whenNotOlder_thenNoWarning() {
        #expect(
            RestoreWarning.evaluate(
                manifest: manifest(sequence: 5, device: "mine"),
                lastLocalSequence: 5,
                localDeviceID: "mine"
            )
                == nil
        )
        #expect(
            RestoreWarning.evaluate(
                manifest: manifest(sequence: 1, device: "other"),
                lastLocalSequence: 9,
                localDeviceID: "mine"
            )
                == nil
        )
        #expect(
            RestoreWarning.evaluate(
                manifest: manifest(sequence: 1, device: "mine"),
                lastLocalSequence: 0,
                localDeviceID: "mine"
            )
                == nil
        )
    }
}
