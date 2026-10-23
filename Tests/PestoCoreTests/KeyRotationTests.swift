// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import Security
import Testing
@testable import PestoCore

@Suite("Replacing the install key")
struct KeyRotationTests {
    private final class Calls: @unchecked Sendable {
        var updates = 0
        var adds = 0
        var stored: Data?
    }

    @Test("a key the Keychain accepted over the old one is the one that is used, and nothing else is added")
    func whenUpdateSucceeds_thenTheNewKeyIsReturnedAndStored() throws {
        let calls = Calls()
        let new = SymmetricKey(size: .bits256)

        let used = try BlobEncryption.replaceKey(
            newKey: new,
            update: { calls.updates += 1
                calls.stored = $0
                return errSecSuccess
            },
            add: { _ in calls.adds += 1
                return errSecSuccess
            }
        )

        #expect(used == new)
        #expect(calls.updates == 1)
        #expect(calls.adds == 0)
        #expect(calls.stored == new.withUnsafeBytes { Data($0) })
    }

    @Test("with no item to update the key is added")
    func whenNoItem_thenAdded() throws {
        let calls = Calls()
        let new = SymmetricKey(size: .bits256)

        let used = try BlobEncryption.replaceKey(
            newKey: new,
            update: { _ in errSecItemNotFound },
            add: { calls.adds += 1
                calls.stored = $0
                return errSecSuccess
            }
        )

        #expect(used == new)
        #expect(calls.adds == 1)
    }

    @Test("a Keychain that refuses leaves the old key in use: nothing is returned to cache")
    func whenKeychainRefuses_thenItThrows() {
        #expect(throws: BlobEncryption.Error.self) {
            try BlobEncryption.replaceKey(
                newKey: SymmetricKey(size: .bits256), update: { _ in errSecInteractionNotAllowed },
                add: { _ in errSecSuccess }
            )
        }
        #expect(throws: BlobEncryption.Error.self) {
            try BlobEncryption.replaceKey(
                newKey: SymmetricKey(size: .bits256), update: { _ in errSecItemNotFound },
                add: { _ in errSecDuplicateItem }
            )
        }
    }

    @Test("what was sealed under the old key does not open under a new one")
    func whenKeyChanges_thenOldCiphertextIsUnreadable() throws {
        let old = BlobEncryptionWithKey(key: SymmetricKey(size: .bits256))
        let new = BlobEncryptionWithKey(key: SymmetricKey(size: .bits256))
        let sealed = try old.encrypt(Data("a deleted clip".utf8), associatedData: Data("id".utf8))

        #expect(try old.decrypt(sealed, associatedData: Data("id".utf8)) == Data("a deleted clip".utf8))
        #expect(throws: BlobEncryption.Error.self) { try new.decrypt(sealed, associatedData: Data("id".utf8)) }
    }

    @Test("a test or UI-test launch keeps its fixed session key, so data written before a relaunch still opens")
    func whenNotANormalLaunch_thenRotationIsANoOp() throws {
        let before = try BlobEncryption().loadOrCreateKey()

        try BlobEncryption().rotateKey()

        #expect(try BlobEncryption().loadOrCreateKey() == before)
    }
}
