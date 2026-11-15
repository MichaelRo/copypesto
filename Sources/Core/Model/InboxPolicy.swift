// SPDX-License-Identifier: MIT
import Foundation
import UniformTypeIdentifiers

/// The bounds of the sealed inbox the share extension writes and the app empties (ADR 0047). A share extension runs
/// under a memory limit near 120 MB, so a picture it keeps is a fifth of what one copy may be on a Mac
/// (`ClipSizePolicy`); a larger one is scaled down to `maxConvertedPixel` on its longer side, or refused.
public enum InboxPolicy {
    public static let textTypeIdentifier = UTType.utf8PlainText.identifier

    /// Picture formats ingest stores as they are; anything else is converted to PNG first.
    public static let storedPictureTypes: Set<String> = [
        UTType.png.identifier, UTType.jpeg.identifier, UTType.heic.identifier, UTType.tiff.identifier,
        UTType.gif.identifier, UTType.webP.identifier
    ]

    public static let maxTextBytes = ClipSizePolicy.maxTextBytes
    public static let maxPictureBytes = 20 * ClipSizePolicy.megabyte
    public static let maxConvertedPixel = 2560
    public static let maxPendingFiles = 50
    public static let maxPendingBytes = 200 * ClipSizePolicy.megabyte
    /// A file the app could not ingest for a reason other than the content (the store would not save) is tried again
    /// at the next activation, and removed once it is this old.
    public static let maxAge: TimeInterval = 7 * 86_400
    static let maxTypeIdentifierBytes = 128

    /// Header, plaintext framing and the AEAD tag around the largest payload.
    public static var maxFileBytes: Int {
        maxPictureBytes + 1024
    }

    public static func accepts(typeIdentifier: String) -> Bool {
        typeIdentifier == textTypeIdentifier || storedPictureTypes.contains(typeIdentifier)
    }

    public static func limit(forTypeIdentifier typeIdentifier: String) -> Int {
        typeIdentifier == textTypeIdentifier ? maxTextBytes : maxPictureBytes
    }
}
