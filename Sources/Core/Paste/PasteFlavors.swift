// SPDX-License-Identifier: MIT
import AppKit

/// A clip is stored under one pasteboard type, but the app receiving the paste may read only the plain-text one:
/// web fields and Electron apps ignore `public.url` and `public.rtf`.
///
/// Main-actor only: AppKit's RTF and RTFD readers are not thread-safe. Parsed on a background thread while other AppKit
/// work ran, `NSRTFReader` aborted a test process with an Objective-C exception.
@MainActor
public enum PasteFlavors {
    public struct ImageFlavor: Sendable {
        public let type: NSPasteboard.PasteboardType
        public let data: Data

        public init(type: NSPasteboard.PasteboardType, data: Data) {
            self.type = type
            self.data = data
        }
    }

    /// Companion image flavours to write alongside the stored type (PNG and TIFF).
    /// Cocoa editors (Notes, Mail, Pages, Keynote) expect `public.tiff` with DPI metadata for sharp Retina 2x
    /// rendering,
    /// while Chromium, Electron and Web apps require `public.png`.
    public static func companionImageFlavors(forStoredType typeIdentifier: String, data: Data) -> [ImageFlavor] {
        autoreleasepool {
            let pbType = NSPasteboard.PasteboardType(typeIdentifier)
            if pbType == .png {
                guard let rep = NSBitmapImageRep(data: data),
                      let tiff = rep.tiffRepresentation(using: .none, factor: 0) else { return [] }
                return [ImageFlavor(type: .tiff, data: tiff)]
            } else if pbType == .tiff {
                guard let rep = NSBitmapImageRep(data: data),
                      let png = rep.representation(using: .png, properties: [:]) else { return [] }
                return [ImageFlavor(type: .png, data: png)]
            } else if pbType.rawValue == "com.compuserve.gif" || pbType.rawValue == "public.gif" {
                // For animated GIFs, write only PNG as a static fallback; omitting TIFF allows Cocoa apps that
                // support GIF animation to preserve it.
                guard let rep = NSBitmapImageRep(data: data),
                      let png = rep.representation(using: .png, properties: [:]) else { return [] }
                return [ImageFlavor(type: .png, data: png)]
            } else if pbType.rawValue == "public.jpeg" || pbType.rawValue == "public.heic"
                || pbType.rawValue == "public.webp" || pbType.rawValue == "org.webmproject.webp"
            {
                guard let rep = NSBitmapImageRep(data: data),
                      let png = rep.representation(using: .png, properties: [:]) else { return [] }
                return [ImageFlavor(type: .png, data: png)]
            }
            return []
        }
    }

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
