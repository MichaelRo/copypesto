// SPDX-License-Identifier: MIT
import Foundation

extension StorageService {
    /// Saves, and when that fails drops the pending changes: SwiftData keeps them in this actor's context, so the next
    /// unrelated save would otherwise commit a half-made clip.
    func saveOrRollback() throws {
        try modelContext.saveOrRollback()
    }

    func sealPreview(_ data: Data, itemID: UUID) throws -> BlobEncryption.EncryptedEnvelope {
        let associatedData = BlobEncryption.associatedData(itemID: itemID, field: .preview)
        if let previewSealer { return try previewSealer(data, associatedData) }
        return try encryption.encrypt(data, associatedData: associatedData)
    }
}
