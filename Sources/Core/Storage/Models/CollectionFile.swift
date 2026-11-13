// SPDX-License-Identifier: MIT
import Foundation

/// What a collection file may hold (ADR 0045). Version 2 adds, per clip, the clip's original data as base64.
public enum CollectionFilePolicy {
    public static let currentVersion = 2
    public static let maxPayloadBytes = UndoPolicy.maxClipBytes
    public static let maxPixels = 50_000_000

    private static let payloadTypes: Set<String> = [
        "public.utf8-plain-text", "public.url", "public.file-url", "public.png", "public.tiff", "public.jpeg",
        "public.heic", "org.webmproject.webp", "public.webp", "com.compuserve.gif", "public.gif", "com.adobe.pdf",
        "public.svg-image"
    ]
    private static let vectorTypes: Set<String> = ["com.adobe.pdf", "public.svg-image"]

    static func isAllowedPayloadType(_ identifier: String) -> Bool {
        payloadTypes.contains(identifier)
    }

    static func isRaster(_ identifier: String) -> Bool {
        isAllowedPayloadType(identifier) && !isText(identifier) && identifier != "public.file-url"
            && !vectorTypes.contains(identifier)
    }

    static func isText(_ identifier: String) -> Bool {
        identifier == "public.utf8-plain-text" || identifier == "public.url"
    }

    /// The longest base64 text that can decode to `maxPayloadBytes`, so an oversized one is refused before decoding.
    static var maxEncodedLength: Int {
        (maxPayloadBytes + 2) / 3 * 4
    }
}

/// A written collection and what was left out of it.
public struct CollectionExportFile: Sendable {
    public let data: Data
    public let exported: Int
    public let skippedSensitive: Int
    public let skippedTooLarge: Int
    public let skippedUnreadable: Int

    public var skipped: Int {
        skippedSensitive + skippedTooLarge + skippedUnreadable
    }
}

/// What an import did, for the message the person reads.
public struct CollectionImportResult: Sendable, Equatable {
    public let collectionID: UUID
    public internal(set) var itemsImported = 0
    public internal(set) var alreadyPresent = 0
    public internal(set) var skippedTooLarge = 0
    public internal(set) var skippedSensitive = 0
    public internal(set) var skippedUnreadable = 0

    public var skipped: Int {
        skippedTooLarge + skippedSensitive + skippedUnreadable
    }

    init(collectionID: UUID) {
        self.collectionID = collectionID
    }
}
