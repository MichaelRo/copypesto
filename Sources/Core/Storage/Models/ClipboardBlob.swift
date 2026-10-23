// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// The heavy payload sibling to `ClipboardItem`. Always encrypted at rest (ADR 0002).
/// `@Attribute(.externalStorage)` causes SwiftData to write the data to a file alongside
/// the SQLite store, and CloudKit mirrors it as a `CKAsset` — streamed, lazy, large-payload-safe.
@Model
public final class ClipboardBlob {
    @Attribute(.unique) public var id: UUID

    @Attribute(.externalStorage) public var encryptedData: Data
    public var nonceData: Data
    public var mimeType: String

    @Attribute(.externalStorage) public var encryptedRichData: Data?
    public var richNonceData: Data?

    public var item: ClipboardItem?

    /// True once the ciphertext is bound to its item (`BlobEncryption.associatedData`); older rows are not, and are
    /// converted by `StorageService.bindCiphertextToItems`.
    public var aadBound: Bool = false

    public init(
        id: UUID = UUID(),
        encryptedData: Data,
        nonceData: Data,
        mimeType: String,
        encryptedRichData: Data? = nil,
        richNonceData: Data? = nil
    ) {
        self.id = id
        self.encryptedData = encryptedData
        self.nonceData = nonceData
        self.mimeType = mimeType
        self.encryptedRichData = encryptedRichData
        self.richNonceData = richNonceData
    }

    /// What this blob's ciphertext is bound to, nil for a row from before binding existed.
    public var associatedData: Data? {
        guard aadBound, let item else { return nil }
        return BlobEncryption.associatedData(itemID: item.id, field: .blob)
    }

    /// Decrypts the blob payload. Returns nil on key-not-found or decryption failure, and for a bound blob that is
    /// no longer attached to its item.
    public func decryptedData() -> Data? {
        guard !aadBound || item != nil else { return nil }
        return try? BlobEncryption().decrypt(
            BlobEncryption.EncryptedEnvelope(ciphertext: encryptedData, nonce: nonceData),
            associatedData: associatedData
        )
    }

    /// Convenience: decrypts and UTF-8 decodes the payload.
    public func decryptedText() -> String? {
        decryptedData().flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Decrypts and decodes the rich text flavours (RTF, RTFD, HTML) stored alongside a plain-text clip.
    public func decryptedRichPayload() -> RichTextPayload? {
        guard !aadBound || item != nil,
              let ciphertext = encryptedRichData,
              let nonce = richNonceData,
              let data = try? BlobEncryption().decrypt(
                  BlobEncryption.EncryptedEnvelope(ciphertext: ciphertext, nonce: nonce),
                  associatedData: associatedData
              ) else { return nil }
        return try? JSONDecoder().decode(RichTextPayload.self, from: data)
    }
}
