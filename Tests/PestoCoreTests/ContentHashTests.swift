// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import Testing
@testable import PestoCore

@Suite("Keyed content hashes")
struct ContentHashTests {
    private let plain = SHA256.hash(data: Data("hello".utf8)).map { String(format: "%02x", $0) }.joined()
    private let keyA = SymmetricKey(data: Data(repeating: 1, count: 32))
    private let keyB = SymmetricKey(data: Data(repeating: 2, count: 32))

    @Test("the stored form is tagged, is not the plain hash, and is stable for one key")
    func whenStored_thenKeyedAndStable() {
        let stored = ContentHash.stored(plain, key: keyA)

        #expect(ContentHash.isKeyed(stored))
        #expect(stored != plain)
        #expect(!stored.contains(plain))
        #expect(stored == ContentHash.stored(plain, key: keyA))
    }

    @Test("a different key gives a different value, so a stolen store cannot be tested against guesses")
    func whenKeyDiffers_thenHashDiffers() {
        #expect(ContentHash.stored(plain, key: keyA) != ContentHash.stored(plain, key: keyB))
    }

    @Test("with no key available the plain hash is kept, so nothing is lost or crashes")
    func whenNoKey_thenPlainKept() {
        #expect(ContentHash.stored(plain, key: nil) == plain)
        #expect(!ContentHash.isKeyed(plain))
    }

    @Test("a stored hash is never hashed twice")
    func whenAlreadyKeyed_thenUnchanged() {
        let stored = ContentHash.stored(plain, key: keyA)

        #expect(ContentHash.stored(stored, key: keyA) == stored)
    }

    @Test("lookups try the keyed form and the plain form, so items from before the change still dedupe")
    func whenLookedUp_thenBothFormsAreCandidates() {
        let forms = ContentHash.candidates(for: plain, key: keyA)

        #expect(forms == [ContentHash.stored(plain, key: keyA), plain])
        #expect(ContentHash.candidates(for: plain, key: nil) == [plain])
    }

    @Test("the migration turns a legacy hash into exactly what a fresh copy of the same content would store")
    func whenMigrated_thenEqualsFreshStoredForm() {
        // Migration has only the old hash, not the content: it must land on the same value ingest computes.
        #expect(ContentHash.migrated(legacy: plain, key: keyA) == ContentHash.stored(plain, key: keyA))
        #expect(ContentHash.migrated(legacy: ContentHash.stored(plain, key: keyA), key: keyA) == nil)
    }
}
