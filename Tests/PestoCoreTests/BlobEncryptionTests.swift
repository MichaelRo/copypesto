// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import Testing
@testable import PestoCore

@Suite("BlobEncryption", .serialized)
struct BlobEncryptionTests {
    @Test("round-trips a plaintext payload")
    func whenEncryptThenDecrypt_thenSamePayload() throws {
        let key = SymmetricKey(size: .bits256)
        let enc = BlobEncryptionWithKey(key: key)
        let plaintext = Data("hello, pesto".utf8)
        let envelope = try enc.encrypt(plaintext)
        let decoded = try enc.decrypt(envelope)
        #expect(decoded == plaintext)
    }

    @Test("ciphertext bytes differ from plaintext bytes (sanity)")
    func whenEncrypted_thenCiphertextDiffers() throws {
        let key = SymmetricKey(size: .bits256)
        let enc = BlobEncryptionWithKey(key: key)
        let plaintext = Data("this should be encrypted".utf8)
        let envelope = try enc.encrypt(plaintext)
        #expect(envelope.ciphertext != plaintext)
        // Ciphertext is plaintext.count + 16 (GCM tag) bytes
        #expect(envelope.ciphertext.count == plaintext.count + 16)
    }

    @Test("nonce is 12 bytes (AES-GCM standard)")
    func nonceIs12Bytes() throws {
        let key = SymmetricKey(size: .bits256)
        let enc = BlobEncryptionWithKey(key: key)
        let envelope = try enc.encrypt(Data("hi".utf8))
        #expect(envelope.nonce.count == 12)
    }

    @Test("decryption with wrong key fails")
    func whenWrongKey_thenDecryptionFails() throws {
        let key1 = SymmetricKey(size: .bits256)
        let key2 = SymmetricKey(size: .bits256)
        let enc1 = BlobEncryptionWithKey(key: key1)
        let enc2 = BlobEncryptionWithKey(key: key2)
        let envelope = try enc1.encrypt(Data("secret".utf8))
        #expect(throws: BlobEncryption.Error.decryptionFailed) {
            _ = try enc2.decrypt(envelope)
        }
    }

    @Test("tampered ciphertext fails authentication")
    func whenCiphertextTampered_thenFails() throws {
        let key = SymmetricKey(size: .bits256)
        let enc = BlobEncryptionWithKey(key: key)
        var envelope = try enc.encrypt(Data("ok".utf8))
        var tampered = Data(envelope.ciphertext) // normalize startIndex to 0
        tampered[0] ^= 0xFF
        envelope = BlobEncryption.EncryptedEnvelope(ciphertext: tampered, nonce: envelope.nonce)
        #expect(throws: BlobEncryption.Error.decryptionFailed) {
            _ = try enc.decrypt(envelope)
        }
    }

    @Test("invalid nonce throws invalidNonce")
    func whenNonceInvalid_thenInvalidNonceError() throws {
        let key = SymmetricKey(size: .bits256)
        let enc = BlobEncryptionWithKey(key: key)
        let badEnvelope = BlobEncryption.EncryptedEnvelope(
            ciphertext: Data(repeating: 0, count: 32),
            nonce: Data(repeating: 0, count: 3) // too short
        )
        #expect(throws: BlobEncryption.Error.invalidNonce) {
            _ = try enc.decrypt(badEnvelope)
        }
    }

    @Test("data sealed with associated data opens only with the same associated data")
    func whenAssociatedData_thenItMustMatch() throws {
        let enc = BlobEncryptionWithKey(key: SymmetricKey(size: .bits256))
        let owner = UUID()
        let other = UUID()
        let context = BlobEncryption.associatedData(itemID: owner, field: .blob)
        let envelope = try enc.encrypt(Data("payload".utf8), associatedData: context)

        #expect(try enc.decrypt(envelope, associatedData: context) == Data("payload".utf8))
        #expect(throws: BlobEncryption.Error.decryptionFailed) {
            _ = try enc.decrypt(envelope, associatedData: BlobEncryption.associatedData(itemID: other, field: .blob))
        }
        #expect(throws: BlobEncryption.Error.decryptionFailed) {
            _ = try enc.decrypt(envelope, associatedData: BlobEncryption.associatedData(itemID: owner, field: .preview))
        }
        #expect(throws: BlobEncryption.Error.decryptionFailed) {
            _ = try enc.decrypt(envelope)
        }
    }

    @Test("data sealed without associated data still opens without it, so older clips stay readable")
    func whenLegacyEnvelope_thenOpensWithoutAssociatedData() throws {
        let enc = BlobEncryptionWithKey(key: SymmetricKey(size: .bits256))
        let envelope = try enc.encrypt(Data("old clip".utf8))

        #expect(try enc.decrypt(envelope, associatedData: nil) == Data("old clip".utf8))
        #expect(throws: BlobEncryption.Error.decryptionFailed) {
            _ = try enc.decrypt(envelope, associatedData: BlobEncryption.associatedData(itemID: UUID(), field: .blob))
        }
    }

    @Test("the associated data names the item and the field, and differs for each")
    func whenBuilt_thenDistinctPerItemAndField() {
        let id = UUID()

        #expect(BlobEncryption.associatedData(itemID: id, field: .blob) != BlobEncryption.associatedData(
            itemID: id,
            field: .preview
        ))
        #expect(BlobEncryption.associatedData(itemID: id, field: .blob) != BlobEncryption.associatedData(
            itemID: UUID(),
            field: .blob
        ))
        #expect(BlobEncryption.associatedData(itemID: id, field: .blob) == BlobEncryption.associatedData(
            itemID: id,
            field: .blob
        ))
    }
}
