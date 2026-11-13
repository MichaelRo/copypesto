// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation

/// What a collection file may hold (ADR 0045). Version 2 adds, per clip, the clip's original data as base64.
public enum CollectionFilePolicy {
    public static let currentVersion = 2
    public static let maxPayloadBytes = UndoPolicy.maxClipBytes
    public static let maxPixels = 50_000_000
    /// Most clips one file holds. An import adds them all as new clips, and the history keeps 500 to 10,000.
    public static let maxClips = 1000
    public static let maxNameLength = 100

    /// A file clip is a path, which names folders on this Mac and points at nothing on another: never written, never
    /// made.
    static let fileURLType = "public.file-url"

    /// SVG is not importable: it is drawn by the system's SVG renderer, and whether that renderer ever fetches a
    /// linked address is not something Pesto can promise.
    private static let payloadTypes: Set<String> = [
        "public.utf8-plain-text", "public.url", "public.png", "public.tiff", "public.jpeg", "public.heic",
        "org.webmproject.webp", "public.webp", "com.compuserve.gif", "public.gif", "com.adobe.pdf"
    ]

    static func isAllowedPayloadType(_ identifier: String) -> Bool {
        payloadTypes.contains(identifier)
    }

    static func isRaster(_ identifier: String) -> Bool {
        isAllowedPayloadType(identifier) && !isText(identifier) && !isPDF(identifier)
    }

    static func isText(_ identifier: String) -> Bool {
        identifier == "public.utf8-plain-text" || identifier == "public.url"
    }

    static func isPDF(_ identifier: String) -> Bool {
        identifier == "com.adobe.pdf"
    }

    static func opensAsPDF(_ data: Data) -> Bool {
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider) else {
            return false
        }
        return document.numberOfPages > 0 && !document.isEncrypted
    }

    /// The longest base64 text that can decode to `maxPayloadBytes`, so an oversized one is refused before decoding.
    static var maxEncodedLength: Int {
        (maxPayloadBytes + 2) / 3 * 4
    }

    // MARK: A collection's own fields, from a file

    /// A name from a file: no control or format (bidi) characters, trimmed, at most `maxNameLength` characters.
    static func sanitizedName(_ name: String) -> String {
        let kept = String(String.UnicodeScalarView(name.unicodeScalars.filter {
            $0.properties.generalCategory != .control && $0.properties.generalCategory != .format
        }))
        let trimmed = String(kept.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
        return trimmed.trimmingCharacters(in: .whitespaces)
    }

    static let defaultName = "Imported collection"
    static let defaultSymbol = "tray.full"

    /// An icon from the list Pesto offers, or one emoji; anything else is the default.
    static func validSymbol(_ symbol: String) -> String {
        if CollectionSymbols.symbols.contains(symbol) { return symbol }
        if symbol.count == 1, CollectionSymbol.isEmoji(symbol) { return symbol }
        return defaultSymbol
    }

    /// Six hex digits, or nil.
    static func validColor(_ hex: String) -> String? {
        let normalized = CollectionPalette.normalized(hex)
        let digits = Set("0123456789ABCDEF")
        return normalized.count == 6 && normalized.allSatisfy(digits.contains) ? normalized : nil
    }
}

/// A written collection and what was left out of it.
public struct CollectionExportFile: Sendable {
    public let data: Data
    public let exported: Int
    public let skippedSensitive: Int
    public let skippedTooLarge: Int
    public let skippedUnreadable: Int
    public let skippedFiles: Int
    public let skippedOverLimit: Int
    /// Pictures in a format the import does not take (SVG), so a file never carries data its own reader refuses.
    public let skippedPictures: Int

    public var skipped: Int {
        skippedSensitive + skippedTooLarge + skippedUnreadable + skippedFiles + skippedOverLimit + skippedPictures
    }
}

/// What an import did, for the message the person reads.
public struct CollectionImportResult: Sendable, Equatable {
    public let collectionID: UUID
    public let collectionName: String
    public internal(set) var itemsImported = 0
    /// Clips the history already held (by content): left where they are, never moved into the collection.
    public internal(set) var alreadyPresent = 0
    public internal(set) var skippedTooLarge = 0
    public internal(set) var skippedSensitive = 0
    public internal(set) var skippedUnreadable = 0
    public internal(set) var skippedFiles = 0

    public var skipped: Int {
        skippedTooLarge + skippedSensitive + skippedUnreadable + skippedFiles
    }

    init(collectionID: UUID, collectionName: String = "") {
        self.collectionID = collectionID
        self.collectionName = collectionName
    }
}

/// What the person is asked before a file is imported.
public struct CollectionImportPreview: Sendable, Equatable {
    public let name: String
    /// Clips the file holds that an import can add (not file references).
    public let importableCount: Int
    /// At most this many of the oldest unpinned clips the retention limit would remove once the file is in.
    public let wouldRemove: Int
    public let limit: Int
}
