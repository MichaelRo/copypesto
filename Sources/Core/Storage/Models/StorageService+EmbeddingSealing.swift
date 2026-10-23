// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

public extension StorageService {
    /// Seals the plaintext search vectors of clips saved before they were encrypted. Each vector is
    /// sealed,
    /// opened again and compared before its plaintext is cleared, so a failure leaves that clip as it was. Rows convert
    /// independently and in batches; idempotent.
    @discardableResult
    func sealEmbeddings(batchSize: Int = 50) async throws -> (sealed: Int, failed: Int) {
        var sealed = 0
        var failed = 0
        let pending = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.embeddingCiphertext == nil && $0.legacyEmbeddingData != nil }
        )
        try await forEachClip(matching: pending, pageSize: batchSize) { item in
            guard let plain = item.legacyEmbeddingData else { return }
            item.embeddingData = plain
            if item.embeddingCiphertext != nil, item.legacyEmbeddingData == nil, item.embeddingData == plain {
                sealed += 1
            } else {
                failed += 1
            }
        }
        return (sealed, failed)
    }
}
