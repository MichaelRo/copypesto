// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import Security
import Testing
@testable import PestoCore

@Suite("Key recovery")
struct KeyRecoveryTests {
    @Test("a present key is always ready")
    func whenKeyPresent_thenReady() {
        #expect(KeyStartupDecision.evaluate(presence: .present, encryptedRowCount: 500) == .ready)
    }

    @Test("no key and no encrypted data is a fresh install")
    func whenNoKeyAndNoData_thenFreshInstall() {
        #expect(KeyStartupDecision.evaluate(presence: .absent, encryptedRowCount: 0) == .freshInstall)
    }

    @Test("no key but encrypted rows means the history can no longer be read")
    func whenNoKeyButRows_thenKeyMissingWithExistingData() {
        #expect(KeyStartupDecision.evaluate(presence: .absent, encryptedRowCount: 3) == .keyMissingWithExistingData)
    }

    @Test("an existing key is used whether or not minting is locked")
    func whenKeyExists_thenUsed() throws {
        let key = SymmetricKey(size: .bits256)

        #expect(try BlobEncryption.resolve(existing: key, mintingLocked: true) == .use(key))
        #expect(try BlobEncryption.resolve(existing: key, mintingLocked: false) == .use(key))
    }

    @Test("a missing key is minted only when minting is allowed")
    func whenKeyMissingAndUnlocked_thenMint() throws {
        #expect(try BlobEncryption.resolve(existing: nil, mintingLocked: false) == .mint)
    }

    @Test("a missing key with minting locked is refused, never replaced")
    func whenKeyMissingAndLocked_thenThrowsKeyMissing() {
        #expect(throws: BlobEncryption.Error.keyMissing) {
            try BlobEncryption.resolve(existing: nil, mintingLocked: true)
        }
    }

    @Test("only a Keychain that says the item is not there means the key is missing")
    func keyPresence_mapsKeychainStatuses() {
        #expect(KeyPresence(status: errSecSuccess) == .present)
        #expect(KeyPresence(status: errSecItemNotFound) == .absent)
        #expect(KeyPresence(status: errSecInteractionNotAllowed) == .unavailable(errSecInteractionNotAllowed))
        #expect(KeyPresence(status: errSecAuthFailed) == .unavailable(errSecAuthFailed))
    }

    @Test("a Keychain that cannot be read is never reported as a missing key, whatever is on disk")
    func whenKeychainUnavailable_thenNeverKeyMissing() {
        #expect(
            KeyStartupDecision.evaluate(presence: .unavailable(errSecInteractionNotAllowed), encryptedRowCount: 500)
                == .keychainUnavailable
        )
        #expect(
            KeyStartupDecision.evaluate(presence: .unavailable(errSecInteractionNotAllowed), encryptedRowCount: 0)
                == .keychainUnavailable
        )
    }

    @Test("a key that exists but opens none of the history is reported, so the person is not left with a blank shelf")
    func whenKeyPresentButOpensNothing_thenKeyDoesNotOpenHistory() {
        #expect(
            KeyStartupDecision.evaluate(presence: .present, encryptedRowCount: 40, canaryOpens: false)
                == .keyDoesNotOpenHistory
        )
        #expect(KeyStartupDecision.evaluate(presence: .present, encryptedRowCount: 40, canaryOpens: true) == .ready)
        #expect(KeyStartupDecision.evaluate(presence: .present, encryptedRowCount: 0, canaryOpens: nil) == .ready)
    }

    @Test("a new key that loses the race to an existing item is replaced by the stored one")
    func mintOrAdopt_adoptsTheStoredKeyOnDuplicate() throws {
        let stored = SymmetricKey(size: .bits256)
        let storedBytes = stored.withUnsafeBytes { Data($0) }
        let fresh = SymmetricKey(size: .bits256)

        let used = try BlobEncryption.mintOrAdopt(
            newKey: fresh, add: { _ in errSecDuplicateItem }, load: { storedBytes }
        )

        #expect(used.withUnsafeBytes { Data($0) } == storedBytes)
    }

    @Test("a new key is used when it is stored; a duplicate nobody can read is an error, not a guess")
    func mintOrAdopt_otherOutcomes() throws {
        let fresh = SymmetricKey(size: .bits256)
        #expect(try BlobEncryption.mintOrAdopt(newKey: fresh, add: { _ in errSecSuccess }, load: { nil }) == fresh)
        #expect(throws: BlobEncryption.Error.keychainAccessFailed(errSecDuplicateItem)) {
            try BlobEncryption.mintOrAdopt(newKey: fresh, add: { _ in errSecDuplicateItem }, load: { nil })
        }
        #expect(throws: BlobEncryption.Error.keychainAccessFailed(errSecAuthFailed)) {
            try BlobEncryption.mintOrAdopt(newKey: fresh, add: { _ in errSecAuthFailed }, load: { nil })
        }
    }
}
