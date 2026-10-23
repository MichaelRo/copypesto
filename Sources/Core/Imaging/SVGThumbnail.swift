// SPDX-License-Identifier: MIT
import AppKit
import UniformTypeIdentifiers

/// ImageIO cannot read SVG, so cards for SVG clips are drawn by `NSImage`, which can. AppKit images are main-actor
/// only.
@MainActor
public enum SVGThumbnail {
    /// `NSImage` parses and draws the whole document on the main actor, so a larger one is not drawn.
    public static let maxBytes = 2_000_000
    public static let maxPixel = 4096

    public static func looksLikeSVG(_ data: Data) -> Bool {
        guard let head = String(bytes: data.prefix(512), encoding: .utf8) else { return false }
        return head.contains("<svg")
    }

    /// Text whose root element is `<svg`, after an optional XML header, doctype and comments.
    public nonisolated static func isSVGDocument(_ text: String) -> Bool {
        var rest = Substring(text.prefix(2048))
        while true {
            rest = rest.drop(while: \.isWhitespace)
            if rest.hasPrefix("<?") || rest.hasPrefix("<!--") || rest.hasPrefix("<!") {
                let closer = rest.hasPrefix("<!--") ? "-->" : ">"
                guard let end = rest.range(of: closer) else { return false }
                rest = rest[end.upperBound...]
            } else {
                break
            }
        }
        return rest.hasPrefix("<svg")
    }

    public static func png(from data: Data, maxPixel: Int) -> Data? {
        guard data.count <= maxBytes, looksLikeSVG(data), let image = NSImage(data: data), image.size.width > 0,
              image.size.height > 0 else { return nil }
        let scale = CGFloat(min(maxPixel, Self.maxPixel)) / max(image.size.width, image.size.height)
        let width = max(1, Int((image.size.width * scale).rounded()))
        let height = max(1, Int((image.size.height * scale).rounded()))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
