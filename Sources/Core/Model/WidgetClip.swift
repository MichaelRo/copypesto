// SPDX-License-Identifier: MIT
import Foundation

/// One clip as the widget draws it (ADR 0052): never its whole content, only what a widget shows.
public struct WidgetClip: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: ClipboardType
    /// The start of the text (or a file's name), at most `WidgetSnapshotPolicy.maxPreviewCharacters`.
    public let text: String
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

    public init(
        id: UUID, kind: ClipboardType, text: String, linkHost: String? = nil, linkPath: String? = nil,
        colorHex: String? = nil, source: String? = nil, date: Date, isPinned: Bool = false, thumbnail: Data? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.linkHost = linkHost
        self.linkPath = linkPath
        self.colorHex = colorHex
        self.source = source
        self.date = date
        self.isPinned = isPinned
        self.thumbnail = thumbnail
    }
}
