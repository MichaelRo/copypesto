// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// Lightweight clipboard metadata. Sync-friendly: all fields are small, fast to fetch, and
/// safe to ship in a CKRecord. The heavy payload lives in `ClipboardBlob` (see ADR 0007).
@Model
public final class ClipboardItem {
    @Attribute(.unique) public var id: UUID
    public var timestamp: Date
    public var typeRaw: String

    public var sourceBundleID: String?
    public var sourceAppName: String?
    /// Legacy: icons are resolved by bundle ID (`SourceIconCache`), never copied onto items. Kept so existing stores
    /// load; `StorageService.clearLegacyIcons()` empties it.
    public var sourceIconData: Data?
    /// Dominant icon color, hex `"#RRGGBB"` — drives the overlay's mesh-gradient glow.
    public var sourceDominantColorHex: String?

    /// First 500 chars (or masked rendering if sensitive). Never the full payload.
    ///
    /// Every preview is stored encrypted in `previewCiphertext` + `previewNonce` and this field is `""`, except a
    /// parsed color and the masked preview of a secret (ADR 0002, `ColorPreviewPolicy`), which stay readable by design.
    /// Readers use `displayPreviewText` to get the plaintext.
    public var previewText: String

    /// AES-GCM ciphertext of the text/code preview. nil for non-text items and for
    /// items captured before this field existed (those fall back to `previewText`).
    /// See ADR 0002 for the encryption boundary.
    public var previewCiphertext: Data?
    /// 12-byte nonce paired with `previewCiphertext`. nil iff `previewCiphertext` is nil.
    public var previewNonce: Data?
    /// True once `previewCiphertext` is bound to this item's id. See `ClipboardBlob.aadBound`.
    public var previewAADBound: Bool = false

    public var sensitivityRaw: String?
    /// Render this instead of `previewText` when `sensitivityRaw != nil`. See ADR 0003.
    public var sensitivityMaskedPreview: String?

    public var contentHash: String
    public var perceptualHash: String?
    public var byteSize: Int
    /// Characters in a text or code clip's full payload (the preview keeps only the first 500). 0 for other
    /// types and for clips captured before this field existed.
    public var textLength: Int = 0
    /// Pixel dimensions for image clips. nil for non-images or unmeasured images.
    public var pixelWidth: Int?
    public var pixelHeight: Int?

    public var deviceID: String
    public var sequenceNumber: Int64

    /// FK to a ClipCollection (originally named `pinboardID`; preserved via originalName).
    @Attribute(originalName: "pinboardID") public var collectionID: UUID?
    public var isPinned: Bool

    /// v2: per-item TTL. Schema-ready, retention pruner respects when set.
    public var expiresAt: Date?
    /// 1–9: maps to the Ctrl+N global hotkey for instant paste. nil = none.
    public var pinnedHotkeyIndex: Int?
    /// The day a ⌃1–9 shortcut was last used to paste this clip. Plain Date at day resolution. nil when no shortcut is
    /// set.
    public var shortcutLastUsedAt: Date?

    /// The search-by-meaning vector (typically 768d Float32) as it was stored before it was sealed into
    /// `embeddingCiphertext`. Read only until `StorageService.sealEmbeddings()` has emptied it; use
    /// `embeddingData`.
    @Attribute(originalName: "embeddingData") public var legacyEmbeddingData: Data?
    /// The sealed search vector, bound to this clip (`ClipboardItem+Embedding.swift`).
    public var embeddingCiphertext: Data?
    public var embeddingNonce: Data?

    @Relationship(deleteRule: .cascade, inverse: \ClipboardBlob.item) public var blob: ClipboardBlob?

    /// Plaintext columns from before titles, notes, tags and page titles were sealed into `metadataCiphertext`.
    /// They are read only until `StorageService.sealItemMetadata()` has emptied them; use
    /// `customTitle`, `userNote`, `tags`, `ogTitle` and `ogSiteName`.
    @Attribute(originalName: "ogTitle") public var legacyOgTitle: String?
    /// <50 KB. URL OpenGraph preview thumb.
    public var ogImageThumbnail: Data?
    @Attribute(originalName: "ogSiteName") public var legacyOgSiteName: String?
    public var detectedLanguage: String?

    public static let svgLanguage = ClipboardType.svgLanguage

    /// A text clip that is an SVG document: its card draws the picture.
    public var isSVGSource: Bool {
        type == .code && detectedLanguage == Self.svgLanguage
    }

    /// Number of times this item has been pasted. Incremented on every paste action.
    public var pasteCount: Int = 0
    @Attribute(originalName: "customTitle") public var legacyCustomTitle: String?
    @Attribute(originalName: "userNote") public var legacyUserNote: String?
    /// Comma-separated tag strings, as stored before sealing.
    @Attribute(originalName: "tagsRaw") public var legacyTagsRaw: String = ""

    /// AES-GCM ciphertext of the user's title, note and tags and the page's title and site name, bound to this item's
    /// id (`ItemMetadata`). nil when none of them is set. Replaces the plaintext columns above.
    public var metadataCiphertext: Data?
    /// 12-byte nonce paired with `metadataCiphertext`.
    public var metadataNonce: Data?

    /// Set at ingest by the link and image screening, or by hand (Mark as Sensitive). `false` default is CloudKit-safe
    /// (property has a default).
    public var isNSFW: Bool = false
    /// True from the moment a picture or a very large text is saved until it has been judged (read, screened, scanned
    /// for secrets). The card is covered meanwhile and no preview is stored (`StorageService.finishAnalysis`).
    public var analysisPending: Bool = false
    /// True when the item arrived via Universal Clipboard (com.apple.is-remote-clipboard marker).
    public var isRemote: Bool = false

    /// Sync (ADR 0018). All optional and nil until sync is on, so nothing changes for a Mac that never uses it.
    /// `changeClock` is the `SyncStamp.encoded` of the last synced change (a local edit, or the remote one that was
    /// applied); `syncFingerprint` says which synced fields that stamp covered, so a write to anything else (an
    /// embedding, a signature, a GIF upgrade) stamps nothing; `syncDirty` marks what is waiting to be written to the
    /// log; `syncEmittedClock` is what was last written; `syncOrigin` is the device a clip arrived from.
    public var changeClock: String?
    public var syncOrigin: String?
    public var syncFingerprint: String?
    public var syncDirty: Bool?
    public var syncEmittedClock: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        type: ClipboardType,
        sourceBundleID: String? = nil,
        sourceAppName: String? = nil,
        sourceDominantColorHex: String? = nil,
        previewText: String,
        sensitivity: SensitivityCategory? = nil,
        sensitivityMaskedPreview: String? = nil,
        contentHash: String,
        perceptualHash: String? = nil,
        byteSize: Int,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        deviceID: String,
        sequenceNumber: Int64,
        collectionID: UUID? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.typeRaw = type.rawValue
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.sourceDominantColorHex = sourceDominantColorHex
        self.previewText = previewText
        self.sensitivityRaw = sensitivity?.rawValue
        self.sensitivityMaskedPreview = sensitivityMaskedPreview
        self.contentHash = contentHash
        self.perceptualHash = perceptualHash
        self.byteSize = byteSize
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.deviceID = deviceID
        self.sequenceNumber = sequenceNumber
        self.collectionID = collectionID
        self.isPinned = isPinned
    }
}

public extension ClipboardItem {
    var type: ClipboardType {
        ClipboardType(rawValue: typeRaw) ?? .text
    }

    var sensitivity: SensitivityCategory? {
        sensitivityRaw.flatMap(SensitivityCategory.init(rawValue:))
    }

    /// What a sensitive card shows. The stored mask keeps what the generic one cannot (the card's last four digits, a
    /// key's label and prefix, the app that hid a credential); the generic mask is for an item with none stored.
    var localizedMaskedPreview: String? {
        guard let cat = sensitivity else { return nil }
        return sensitivityMaskedPreview ?? SensitiveContentDetector.localizedMask(for: cat, count: textLength)
    }

    var previewAssociatedData: Data? {
        previewAADBound ? BlobEncryption.associatedData(itemID: id, field: .preview) : nil
    }

    /// `gridPreview` folded for search, cached for encrypted previews so filtering thousands of items stays fast.
    var searchableGridPreview: String {
        if sensitivityMaskedPreview == nil, let ciphertext = previewCiphertext, let nonce = previewNonce,
           let folded = PreviewTextCache.shared.folded(id: id, nonce: nonce, decrypt: {
               let envelope = BlobEncryption.EncryptedEnvelope(ciphertext: ciphertext, nonce: nonce)
               return (try? BlobEncryption().decrypt(envelope, associatedData: previewAssociatedData))
                   .flatMap { String(data: $0, encoding: .utf8) }
           })
        {
            return folded
        }
        guard let category = sensitivity,
              sensitivityMaskedPreview != nil else { return SearchMatching.fold(gridPreview) }
        return SearchMatching.fold("\(gridPreview) \(category.searchName)")
    }

    /// The string the grid should render. Enforced by a swiftlint custom rule:
    /// `Features/Grid/*` must use `gridPreview`, never `previewText` directly.
    var gridPreview: String {
        sensitivityMaskedPreview ?? displayPreviewText
    }

    /// Returns the plaintext preview, decrypting `previewCiphertext` if present.
    /// Used everywhere that needs the actual human-readable preview — search, semantic
    /// embedding, Spotlight, AppleScript exposers, etc. For text/code items captured
    /// after ADR 0002 lands this round-trips through `BlobEncryption`; for non-text
    /// items and pre-migration text items it returns the stored `previewText` directly.
    var displayPreviewText: String {
        guard let ciphertext = previewCiphertext, let nonce = previewNonce else {
            return previewText
        }
        let text = PreviewTextCache.shared.text(id: id, nonce: nonce) {
            let envelope = BlobEncryption.EncryptedEnvelope(ciphertext: ciphertext, nonce: nonce)
            return (try? BlobEncryption().decrypt(envelope, associatedData: previewAssociatedData))
                .flatMap { String(data: $0, encoding: .utf8) }
        }
        return text ?? previewText
    }

    /// True when this pinned item contains `{{placeholder}}` tokens — i.e. it's a snippet/template.
    var isTemplate: Bool {
        isPinned && displayPreviewText.contains("{{")
    }

    /// MIME type exposed for `PredicateEvaluatable` — reads through to the associated blob.
    var mimeType: String? {
        blob?.mimeType
    }
}

// MARK: - PredicateEvaluatable

extension ClipboardItem: PredicateEvaluatable {}
