// SPDX-License-Identifier: MIT
import AppKit
import ImageIO

/// Pictures for cards, decoded before the card is drawn. An `NSImage` made from data decodes on its first draw, on the
/// main thread, in the middle of the scroll that brought the card into view; this decodes off it and hands back a
/// bitmap that is ready to draw.
enum PreparedImage {
    static func image(from data: Data, animated: Bool = false) async -> NSImage? {
        if animated { return NSImage(data: data) }
        guard let bitmap = await Task.detached(priority: .userInitiated, operation: { decode(data) }).value else {
            return nil
        }
        return NSImage(cgImage: bitmap, size: NSSize(width: bitmap.width, height: bitmap.height))
    }

    nonisolated static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        return CGImageSourceCreateImageAtIndex(source, 0, options)
    }
}
