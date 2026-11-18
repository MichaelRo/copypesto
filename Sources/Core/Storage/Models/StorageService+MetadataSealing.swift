// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

public extension StorageService {
    /// Encrypts previews stored in plaintext before every type was encrypted (URLs, images, files, and text from
    /// before ADR 0002). Idempotent; sensitive items keep their masked preview and colours stay plain.
    @discardableResult
    func encryptLegacyPreviews() async throws -> Int {
        let colorRaw = ClipboardType.color.rawValue
        var changed = 0
        try await forEachClip(matching: FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.previewCiphertext == nil && !$0.previewText.isEmpty && $0.typeRaw != colorRaw }
        )) { item in
            guard item.sensitivityRaw == nil else { return }
            let envelope = try encryption.encrypt(
                Data(item.previewText.utf8),
                associatedData: BlobEncryption.associatedData(itemID: item.id, field: .preview)
            )
            item.previewCiphertext = envelope.ciphertext
            item.previewNonce = envelope.nonce
            item.previewAADBound = true
            item.previewText = ""
            changed += 1
        }
        return changed
    }

    /// Seals the plaintext title, note, tag and page-title columns of clips saved before they were encrypted.
    /// Each clip is sealed, opened again and compared before its plaintext is cleared, so a failure
    /// leaves that clip as it was. Rows convert independently and in batches; idempotent.
    @discardableResult
    func sealItemMetadata(batchSize: Int = 50) async throws -> (sealed: Int, failed: Int) {
        var sealed = 0
        var failed = 0
        try await forEachClip(pageSize: batchSize) { item in
            guard item.metadataCiphertext == nil else { return }
            let before = item.legacyMetadata
            if before.isEmpty { return }
            item.updateMetadata { _ in }
            if item.metadataCiphertext != nil, item.metadata == before {
                sealed += 1
            } else {
                failed += 1
            }
        }
        return (sealed, failed)
    }
}
