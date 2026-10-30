// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// Everything stored about a deleted clip, copied as it was stored: the sealed bytes stay sealed, so the stack holds
/// no plaintext. Ciphertext is bound to the clip's id (ADR 0002), so a restore reuses the id.
public struct ClipSnapshot: Sendable {
    /// The `ClipboardItem` columns copied here. `ClipSnapshotTests` compares this list with the model's schema, so a
    /// new column fails there until it is copied.
    static let coveredColumns: Set<String> = [
        "id", "timestamp", "typeRaw", "sourceBundleID", "sourceAppName", "sourceIconData", "sourceDominantColorHex",
        "previewText", "previewCiphertext", "previewNonce", "previewAADBound", "sensitivityRaw",
        "sensitivityMaskedPreview", "contentHash", "perceptualHash", "byteSize", "textLength", "pixelWidth",
        "pixelHeight", "deviceID", "sequenceNumber", "collectionID", "isPinned", "expiresAt", "pinnedHotkeyIndex",
        "shortcutLastUsedAt", "legacyEmbeddingData", "embeddingCiphertext", "embeddingNonce", "blob", "legacyOgTitle",
        "ogImageThumbnail", "legacyOgSiteName", "detectedLanguage", "pasteCount", "legacyCustomTitle", "legacyUserNote",
        "legacyTagsRaw", "metadataCiphertext", "metadataNonce", "isNSFW", "analysisPending", "isRemote"
    ]

    /// Columns that sync owns. A restored clip is stamped again by the journal as a new change, so they are not copied.
    static let syncColumns: Set<String> = [
        "changeClock", "syncOrigin", "syncFingerprint", "syncDirty", "syncEmittedClock"
    ]

    public struct Blob: Sendable {
        let id: UUID
        let encryptedData: Data
        let nonceData: Data
        let mimeType: String
        let encryptedRichData: Data?
        let richNonceData: Data?
        let aadBound: Bool
    }

    public let id: UUID
    let timestamp: Date
    let typeRaw: String
    let sourceBundleID: String?
    let sourceAppName: String?
    let sourceIconData: Data?
    let sourceDominantColorHex: String?
    let previewText: String
    let previewCiphertext: Data?
    let previewNonce: Data?
    let previewAADBound: Bool
    let sensitivityRaw: String?
    let sensitivityMaskedPreview: String?
    public let contentHash: String
    let perceptualHash: String?
    let byteSize: Int
    let textLength: Int
    let pixelWidth: Int?
    let pixelHeight: Int?
    let deviceID: String
    let sequenceNumber: Int64
    let collectionID: UUID?
    let isPinned: Bool
    let expiresAt: Date?
    let pinnedHotkeyIndex: Int?
    let shortcutLastUsedAt: Date?
    let legacyEmbeddingData: Data?
    let embeddingCiphertext: Data?
    let embeddingNonce: Data?
    let legacyOgTitle: String?
    let ogImageThumbnail: Data?
    let legacyOgSiteName: String?
    let detectedLanguage: String?
    let pasteCount: Int
    let legacyCustomTitle: String?
    let legacyUserNote: String?
    let legacyTagsRaw: String
    let metadataCiphertext: Data?
    let metadataNonce: Data?
    let isNSFW: Bool
    let analysisPending: Bool
    let isRemote: Bool
    let blob: Blob?
    /// The link preview image file as it is on disk (sealed), restored beside the clip.
    let linkPreviewFile: Data?

    /// Whether `UndoPolicy` allows this clip to be kept.
    var isHoldable: Bool {
        UndoPolicy.canHold(
            byteSize: byteSize, expiresAt: expiresAt, sensitivityRaw: sensitivityRaw, analysisPending: analysisPending
        )
    }

    /// Bytes this snapshot keeps in memory, for the stack's budget.
    public var heldBytes: Int {
        let parts: [Int?] = [
            blob?.encryptedData.count, blob?.encryptedRichData?.count, previewCiphertext?.count,
            metadataCiphertext?.count, embeddingCiphertext?.count, legacyEmbeddingData?.count,
            ogImageThumbnail?.count, sourceIconData?.count, linkPreviewFile?.count
        ]
        return parts.reduce(1024) { $0 + ($1 ?? 0) }
    }

    init(item: ClipboardItem, linkPreviewFile: Data?) {
        id = item.id
        timestamp = item.timestamp
        typeRaw = item.typeRaw
        sourceBundleID = item.sourceBundleID
        sourceAppName = item.sourceAppName
        sourceIconData = item.sourceIconData
        sourceDominantColorHex = item.sourceDominantColorHex
        previewText = item.previewText
        previewCiphertext = item.previewCiphertext
        previewNonce = item.previewNonce
        previewAADBound = item.previewAADBound
        sensitivityRaw = item.sensitivityRaw
        sensitivityMaskedPreview = item.sensitivityMaskedPreview
        contentHash = item.contentHash
        perceptualHash = item.perceptualHash
        byteSize = item.byteSize
        textLength = item.textLength
        pixelWidth = item.pixelWidth
        pixelHeight = item.pixelHeight
        deviceID = item.deviceID
        sequenceNumber = item.sequenceNumber
        collectionID = item.collectionID
        isPinned = item.isPinned
        expiresAt = item.expiresAt
        pinnedHotkeyIndex = item.pinnedHotkeyIndex
        shortcutLastUsedAt = item.shortcutLastUsedAt
        legacyEmbeddingData = item.legacyEmbeddingData
        embeddingCiphertext = item.embeddingCiphertext
        embeddingNonce = item.embeddingNonce
        legacyOgTitle = item.legacyOgTitle
        ogImageThumbnail = item.ogImageThumbnail
        legacyOgSiteName = item.legacyOgSiteName
        detectedLanguage = item.detectedLanguage
        pasteCount = item.pasteCount
        legacyCustomTitle = item.legacyCustomTitle
        legacyUserNote = item.legacyUserNote
        legacyTagsRaw = item.legacyTagsRaw
        metadataCiphertext = item.metadataCiphertext
        metadataNonce = item.metadataNonce
        isNSFW = item.isNSFW
        analysisPending = item.analysisPending
        isRemote = item.isRemote
        blob = item.blob.map {
            Blob(
                id: $0.id, encryptedData: $0.encryptedData, nonceData: $0.nonceData, mimeType: $0.mimeType,
                encryptedRichData: $0.encryptedRichData, richNonceData: $0.richNonceData, aadBound: $0.aadBound
            )
        }
        self.linkPreviewFile = linkPreviewFile
    }

    /// A new, uninserted clip with the stored columns and its blob; the caller inserts it.
    func makeItem() -> ClipboardItem {
        let item = ClipboardItem(
            id: id, timestamp: timestamp, type: ClipboardType(rawValue: typeRaw) ?? .text,
            sourceBundleID: sourceBundleID, sourceAppName: sourceAppName,
            sourceDominantColorHex: sourceDominantColorHex, previewText: previewText,
            sensitivity: nil, sensitivityMaskedPreview: sensitivityMaskedPreview, contentHash: contentHash,
            perceptualHash: perceptualHash, byteSize: byteSize, pixelWidth: pixelWidth, pixelHeight: pixelHeight,
            deviceID: deviceID, sequenceNumber: sequenceNumber, collectionID: collectionID, isPinned: isPinned
        )
        item.typeRaw = typeRaw
        item.sensitivityRaw = sensitivityRaw
        item.sourceIconData = sourceIconData
        item.previewCiphertext = previewCiphertext
        item.previewNonce = previewNonce
        item.previewAADBound = previewAADBound
        item.textLength = textLength
        item.expiresAt = expiresAt
        item.pinnedHotkeyIndex = pinnedHotkeyIndex
        item.shortcutLastUsedAt = shortcutLastUsedAt
        item.legacyEmbeddingData = legacyEmbeddingData
        item.embeddingCiphertext = embeddingCiphertext
        item.embeddingNonce = embeddingNonce
        item.legacyOgTitle = legacyOgTitle
        item.ogImageThumbnail = ogImageThumbnail
        item.legacyOgSiteName = legacyOgSiteName
        item.detectedLanguage = detectedLanguage
        item.pasteCount = pasteCount
        item.legacyCustomTitle = legacyCustomTitle
        item.legacyUserNote = legacyUserNote
        item.legacyTagsRaw = legacyTagsRaw
        item.metadataCiphertext = metadataCiphertext
        item.metadataNonce = metadataNonce
        item.isNSFW = isNSFW
        item.analysisPending = analysisPending
        item.isRemote = isRemote
        if let blob {
            let restored = ClipboardBlob(
                id: blob.id, encryptedData: blob.encryptedData, nonceData: blob.nonceData, mimeType: blob.mimeType,
                encryptedRichData: blob.encryptedRichData, richNonceData: blob.richNonceData
            )
            restored.aadBound = blob.aadBound
            item.blob = restored
        }
        return item
    }

    /// Sets a clip back to the text this snapshot holds (its blob, preview, hash, masking and sealed metadata) and
    /// leaves what the person did around it alone: its collection, pin, shortcut, counts and place in the history.
    func writeContent(to item: ClipboardItem, in context: ModelContext) {
        item.typeRaw = typeRaw
        item.detectedLanguage = detectedLanguage
        item.byteSize = byteSize
        item.textLength = textLength
        item.contentHash = contentHash
        item.sensitivityRaw = sensitivityRaw
        item.sensitivityMaskedPreview = sensitivityMaskedPreview
        item.previewText = previewText
        item.previewCiphertext = previewCiphertext
        item.previewNonce = previewNonce
        item.previewAADBound = previewAADBound
        item.legacyEmbeddingData = legacyEmbeddingData
        item.embeddingCiphertext = embeddingCiphertext
        item.embeddingNonce = embeddingNonce
        item.metadataCiphertext = metadataCiphertext
        item.metadataNonce = metadataNonce
        guard let blob else { return }
        if let current = item.blob {
            current.encryptedData = blob.encryptedData
            current.nonceData = blob.nonceData
            current.mimeType = blob.mimeType
            current.encryptedRichData = blob.encryptedRichData
            current.richNonceData = blob.richNonceData
            current.aadBound = blob.aadBound
        } else {
            let restored = ClipboardBlob(
                id: blob.id, encryptedData: blob.encryptedData, nonceData: blob.nonceData, mimeType: blob.mimeType,
                encryptedRichData: blob.encryptedRichData, richNonceData: blob.richNonceData
            )
            restored.aadBound = blob.aadBound
            context.insert(restored)
            item.blob = restored
        }
    }
}
