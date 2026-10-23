// SPDX-License-Identifier: MIT
import Foundation

/// One item read from the Paste app's local store by `PasteLibraryReader`: its pasteboard
/// representations (UTI → raw bytes, base64-encoded). Import picks the primary representation via
/// `PasteboardTypeDetector` so classification matches live capture exactly.
/// See `decisions/0011-read-only-surfaces.md`.
public struct PasteImportRecord: Codable, Sendable {
    public struct Representation: Codable, Sendable {
        public let uti: String
        public let dataBase64: String

        public init(uti: String, dataBase64: String) {
            self.uti = uti
            self.dataBase64 = dataBase64
        }
    }

    /// Source pinboard name, which becomes the target Collection name on import. `nil` for Paste's
    /// clipboard history, whose items are imported unpinned and in no collection.
    public let pinboard: String?
    /// Optional user-assigned title; imported as `ClipboardItem.customTitle` when present.
    public let title: String?
    public let timestamp: Date
    public let sourceBundleID: String?
    public let representations: [Representation]

    public init(
        pinboard: String?,
        title: String?,
        timestamp: Date,
        sourceBundleID: String?,
        representations: [Representation]
    ) {
        self.pinboard = pinboard
        self.title = title
        self.timestamp = timestamp
        self.sourceBundleID = sourceBundleID
        self.representations = representations
    }
}
