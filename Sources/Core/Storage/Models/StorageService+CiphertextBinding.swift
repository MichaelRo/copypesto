// SPDX-License-Identifier: MIT
import Foundation

extension StorageService {
    /// Binds every clip's ciphertext to its item. Each field is decrypted the old way, sealed again with
    /// the item's id as associated data, and checked by opening it before anything is replaced, so a failure leaves
    /// that clip exactly as it was. Rows convert independently and in batches, so an interrupted run only leaves
    /// some clips unconverted, which stay readable. Idempotent.
    @discardableResult
    public func bindCiphertextToItems(batchSize: Int = 50) async throws -> (converted: Int, failed: Int) {
        var converted = 0
        var failed = 0
        try await forEachClip(pageSize: batchSize) { item in
            if let ciphertext = item.previewCiphertext, let nonce = item.previewNonce, !item.previewAADBound {
                let context = BlobEncryption.associatedData(itemID: item.id, field: .preview)
                if let sealed = rebind(ciphertext: ciphertext, nonce: nonce, context: context) {
                    item.previewCiphertext = sealed.ciphertext
                    item.previewNonce = sealed.nonce
                    item.previewAADBound = true
                    converted += 1
                } else {
                    failed += 1
                }
            }
            if let blob = item.blob, !blob.aadBound {
                let context = BlobEncryption.associatedData(itemID: item.id, field: .blob)
                if let sealed = rebind(ciphertext: blob.encryptedData, nonce: blob.nonceData, context: context) {
                    blob.encryptedData = sealed.ciphertext
                    blob.nonceData = sealed.nonce
                    blob.aadBound = true
                    converted += 1
                } else {
                    failed += 1
                }
            }
        }
        return (converted, failed)
    }

    private func rebind(ciphertext: Data, nonce: Data, context: Data) -> BlobEncryption.EncryptedEnvelope? {
        guard let plain = try? encryption.decrypt(.init(ciphertext: ciphertext, nonce: nonce)),
              let sealed = try? encryption.encrypt(plain, associatedData: context),
              (try? encryption.decrypt(sealed, associatedData: context)) == plain else { return nil }
        return sealed
    }
}
