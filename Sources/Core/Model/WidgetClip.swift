// SPDX-License-Identifier: MIT
import Foundation

/// One clip as the widget draws it (ADR 0052): what a widget shows, and a short text's whole content so a tile can
/// copy it in place.
public struct WidgetClip: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: ClipboardType
    /// The start of the text (or a file's name), at most `WidgetSnapshotPolicy.maxPreviewCharacters`.
    public let text: String
    /// The whole text of a text, code, link or color clip of at most `WidgetSnapshotPolicy.maxFullTextBytes`, while
    /// the snapshot's budget lasts; nil for anything else, which a tile copies by opening Pesto.
    public let fullText: String?
    public let linkHost: String?
    public let linkPath: String?
    /// Six hex digits, without `#`.
    public let colorHex: String?
    /// The app it came from, "Another device", or how it came in on this device.
    public let source: String?
    public let date: Date
    public let isPinned: Bool
    /// A JPEG at most `WidgetSnapshotPolicy.thumbnailMaxPixel` on its longer side.
    public let thumbnail: Data?
    /// The app it came from, a key of `WidgetSnapshot.appIcons` (ADR 0074).
    public let sourceBundleID: String?
    /// The app's color as `#RRGGBB`, for the card's foot glow (ADR 0068).
    public let sourceColorHex: String?

    public init(
        id: UUID, kind: ClipboardType, text: String, fullText: String? = nil, linkHost: String? = nil,
        linkPath: String? = nil, colorHex: String? = nil, source: String? = nil, date: Date, isPinned: Bool = false,
        thumbnail: Data? = nil, sourceBundleID: String? = nil, sourceColorHex: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.fullText = fullText
        self.linkHost = linkHost
        self.linkPath = linkPath
        self.colorHex = colorHex
        self.source = source
        self.date = date
        self.isPinned = isPinned
        self.thumbnail = thumbnail
        self.sourceBundleID = sourceBundleID
        self.sourceColorHex = sourceColorHex
    }
}
