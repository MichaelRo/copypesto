// SPDX-License-Identifier: MIT
import AppKit

/// Classifies a pasteboard's contents into a `ClipboardType` using the priority order
/// expected of macOS pasteboards. Higher priority = more specific representation;
/// we always read the most specific available form.
public enum PasteboardTypeDetector {
    /// Iteration order matters. Examples:
    /// - Finder copies set both `.fileURL` and `.URL`; we want `.fileURL`.
    /// - Browsers set both `.string` and `.URL`; for a URL we want the URL representation.
    /// - Rich text sources set both `.rtf` and `.string`; we currently flatten to text.
    public static let priorityOrder: [NSPasteboard.PasteboardType] = [
        .fileURL,
        // A browser copying a GIF also offers a still PNG or TIFF of it; the GIF is the one that moves.
        NSPasteboard.PasteboardType("com.compuserve.gif"),
        NSPasteboard.PasteboardType("public.gif"),
        .png,
        .tiff,
        NSPasteboard.PasteboardType("public.jpeg"),
        NSPasteboard.PasteboardType("public.heic"),
        NSPasteboard.PasteboardType("org.webmproject.webp"),
        NSPasteboard.PasteboardType("public.webp"),
        .URL,
        .rtf,
        .rtfd,
        .string,
        // Vector formats are a last resort: apps that put text on the board often add a PDF of it too.
        NSPasteboard.PasteboardType("com.adobe.pdf"),
        NSPasteboard.PasteboardType("public.svg-image")
    ]

    /// The first matching pasteboard type, or nil if none of the priority types are present.
    public static func detect(types: [NSPasteboard.PasteboardType]) -> NSPasteboard.PasteboardType? {
        let set = Set(types)
        return priorityOrder.first(where: set.contains)
    }

    /// Maps a pasteboard type to a `ClipboardType`. Returns nil for unsupported types.
    public static func clipboardType(for pasteboardType: NSPasteboard.PasteboardType) -> ClipboardType? {
        switch pasteboardType {
        case .fileURL: .file
        case .png, .tiff,
             NSPasteboard.PasteboardType("public.jpeg"),
             NSPasteboard.PasteboardType("public.heic"),
             NSPasteboard.PasteboardType("org.webmproject.webp"),
             NSPasteboard.PasteboardType("public.webp"),
             NSPasteboard.PasteboardType("com.compuserve.gif"),
             NSPasteboard.PasteboardType("public.gif"),
             NSPasteboard.PasteboardType("com.adobe.pdf"),
             NSPasteboard.PasteboardType("public.svg-image"): .image
        case .URL: .url
        case .rtf, .rtfd, .string: .text
        default: nil
        }
    }
}
