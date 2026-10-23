// SPDX-License-Identifier: MIT
import AppKit

/// A clip is stored under one pasteboard type, but the app receiving the paste may read only the plain-text one:
/// web fields and Electron apps ignore `public.url` and `public.rtf`.
///
/// Main-actor only: AppKit's RTF and RTFD readers are not thread-safe. Parsed on a background thread while other AppKit
/// work ran, `NSRTFReader` aborted a test process with an Objective-C exception.
@MainActor
public enum PasteFlavors {
    /// The plain-text flavour to write next to the stored type; nil when the stored type is already text or is
    /// not textual (images, files).
    public static func plainText(forStoredType typeIdentifier: String, data: Data) -> String? {
        switch NSPasteboard.PasteboardType(typeIdentifier) {
        case .URL:
            String(data: data, encoding: .utf8)
        case .rtf:
            flattened(data, as: .rtf)
        case .rtfd:
            flattened(data, as: .rtfd)
        case .html:
            flattened(data, as: .html)
        default:
            nil
        }
    }

    private static func flattened(_ data: Data, as type: NSAttributedString.DocumentType) -> String? {
        try? NSAttributedString(data: data, options: [.documentType: type], documentAttributes: nil).string
    }
}
