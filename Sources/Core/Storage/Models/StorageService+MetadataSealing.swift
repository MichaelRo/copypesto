// SPDX-License-Identifier: MIT
import Foundation

public extension StorageService {
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
