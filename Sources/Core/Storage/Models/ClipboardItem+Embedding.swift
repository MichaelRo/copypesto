// SPDX-License-Identifier: MIT
import Foundation
import os

private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "ItemEmbedding")

public extension ClipboardItem {
    /// The search vector, opened once per ciphertext. A clip whose vector does not open (moved from another row, or the
    /// key is gone) reads as having none; one not yet sealed reads its plaintext column.
    ///
    /// Writing seals the vector. If sealing is impossible (no key) it is kept in the plaintext column rather than lost,
    /// and the next launch seals it.
    var embeddingData: Data? {
        get {
            guard let ciphertext = embeddingCiphertext, let nonce = embeddingNonce else { return legacyEmbeddingData }
            return PreviewTextCache.shared.embedding(id: id, nonce: nonce) {
                let envelope = BlobEncryption.EncryptedEnvelope(ciphertext: ciphertext, nonce: nonce)
                return try? BlobEncryption().decrypt(
                    envelope, associatedData: BlobEncryption.associatedData(itemID: id, field: .embedding)
                )
            }
        }
        set {
            guard let newValue else {
                embeddingCiphertext = nil
                embeddingNonce = nil
                legacyEmbeddingData = nil
                return
            }
            do {
                let sealed = try BlobEncryption().encrypt(
                    newValue, associatedData: BlobEncryption.associatedData(itemID: id, field: .embedding)
                )
                embeddingCiphertext = sealed.ciphertext
                embeddingNonce = sealed.nonce
                legacyEmbeddingData = nil
            } catch {
                logger.error("Could not seal a search vector: \(error.localizedDescription, privacy: .public)")
                embeddingCiphertext = nil
                embeddingNonce = nil
                legacyEmbeddingData = newValue
            }
        }
    }
}
