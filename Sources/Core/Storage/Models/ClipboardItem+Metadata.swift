// SPDX-License-Identifier: MIT
import Foundation
import os

private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "ItemMetadata")

public extension ClipboardItem {
    var metadataAssociatedData: Data {
        BlobEncryption.associatedData(itemID: id, field: .metadata)
    }

    /// The title, note, tags and page title, opened once per ciphertext. A clip whose metadata does not open (moved
    /// from another row, or the key is gone) reads as having none.
    var metadata: ItemMetadata {
        guard metadataCiphertext != nil else { return legacyMetadata }
        return openedMetadata ?? ItemMetadata()
    }

    /// True when sealed metadata exists but cannot be opened. Such a clip reads as having none, and must not be
    /// edited: the edit would be built from nothing and replace what is still there under a key that may come back.
    var metadataIsUnreadable: Bool {
        metadataCiphertext != nil && openedMetadata == nil
    }

    private var openedMetadata: ItemMetadata? {
        guard let ciphertext = metadataCiphertext, let nonce = metadataNonce else { return nil }
        return PreviewTextCache.shared.metadata(id: id, nonce: nonce) {
            let envelope = BlobEncryption.EncryptedEnvelope(ciphertext: ciphertext, nonce: nonce)
            return (try? BlobEncryption().decrypt(envelope, associatedData: metadataAssociatedData))
                .flatMap { try? JSONDecoder().decode(ItemMetadata.self, from: $0) }
        }
    }

    /// The plaintext columns as they were stored before sealing.
    var legacyMetadata: ItemMetadata {
        ItemMetadata(
            customTitle: legacyCustomTitle, userNote: legacyUserNote, tags: ItemMetadata.parseTags(legacyTagsRaw),
            ogTitle: legacyOgTitle, ogSiteName: legacyOgSiteName
        )
    }

    /// Changes the metadata and seals the result. It fails closed: metadata that exists but cannot be opened is left
    /// as it is, and if sealing fails the edit is dropped. Neither wipes what is stored or writes it in the clear.
    func updateMetadata(
        sealing seal: (Data, Data) throws -> BlobEncryption.EncryptedEnvelope = { plaintext, associatedData in
            try BlobEncryption().encrypt(plaintext, associatedData: associatedData)
        },
        _ change: (inout ItemMetadata) -> Void
    ) {
        guard !metadataIsUnreadable else {
            logger.error("Item metadata does not open; the edit was not applied")
            return
        }
        var value = metadata
        change(&value)
        value.tags = value.tags.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        store(value, sealing: seal)
    }

    private func store(_ value: ItemMetadata, sealing seal: (Data, Data) throws -> BlobEncryption.EncryptedEnvelope) {
        if value.isEmpty {
            metadataCiphertext = nil
            metadataNonce = nil
            clearLegacyMetadata()
            return
        }
        do {
            let sealed = try seal(JSONEncoder().encode(value), metadataAssociatedData)
            metadataCiphertext = sealed.ciphertext
            metadataNonce = sealed.nonce
            clearLegacyMetadata()
        } catch {
            let reason = error.localizedDescription
            logger.error("Metadata not sealed, edit dropped: \(reason, privacy: .public)")
        }
    }

    private func clearLegacyMetadata() {
        if legacyCustomTitle != nil { legacyCustomTitle = nil }
        if legacyUserNote != nil { legacyUserNote = nil }
        if !legacyTagsRaw.isEmpty { legacyTagsRaw = "" }
        if legacyOgTitle != nil { legacyOgTitle = nil }
        if legacyOgSiteName != nil { legacyOgSiteName = nil }
    }

    var customTitle: String? {
        get { metadata.customTitle }
        set { if metadata.customTitle != newValue { updateMetadata { $0.customTitle = newValue } } }
    }

    var customSymbolName: String? {
        get { metadata.customSymbolName }
        set { if metadata.customSymbolName != newValue { updateMetadata { $0.customSymbolName = newValue } } }
    }

    var offersCustomIcon: Bool {
        collectionID != nil || customSymbolName != nil
    }

    var userNote: String? {
        get { metadata.userNote }
        set { if metadata.userNote != newValue { updateMetadata { $0.userNote = newValue } } }
    }

    var ogTitle: String? {
        get { metadata.ogTitle }
        set { if metadata.ogTitle != newValue { updateMetadata { $0.ogTitle = newValue } } }
    }

    var ogSiteName: String? {
        get { metadata.ogSiteName }
        set { if metadata.ogSiteName != newValue { updateMetadata { $0.ogSiteName = newValue } } }
    }

    var tags: [String] {
        get { metadata.tags }
        set { if metadata.tags != newValue { updateMetadata { $0.tags = newValue } } }
    }

    var linkPreviewFetched: Bool {
        get { metadata.linkPreviewFetched ?? false }
        set { if metadata.linkPreviewFetched != newValue { updateMetadata { $0.linkPreviewFetched = newValue } } }
    }

    var collectionOrder: Int? {
        get { metadata.collectionOrder }
        set { if metadata.collectionOrder != newValue { updateMetadata { $0.collectionOrder = newValue } } }
    }
}
