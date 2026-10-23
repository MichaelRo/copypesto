// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// Produces card thumbnails off the main thread. The blob's file read, the decryption and the decode all happen here;
/// the card only receives a small PNG.
@ModelActor
public actor ThumbnailService {
    public struct Thumbnail: Sendable {
        public let data: Data
        public let isAnimated: Bool
    }

    private static let maxAnimatedFrames = 60
    private nonisolated(unsafe) static let animatedPreviews: NSCache<NSUUID, NSData> = {
        let cache = NSCache<NSUUID, NSData>()
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    public func thumbnail(for itemID: UUID, maxPixel: Int) async -> Thumbnail? {
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == itemID })
        descriptor.fetchLimit = 1
        guard let blob = (try? modelContext.fetch(descriptor))?.first?.blob,
              let imageData = blob.decryptedData() else { return nil }
        let isAnimated = blob.mimeType == "com.compuserve.gif" || blob.mimeType == "public.gif" || imageData.isGIF
        if isAnimated {
            // The shelf plays a scaled, frame-capped copy: a copied GIF can be tens of megabytes, and every visible
            // card decodes its frames. The stored original is what gets pasted.
            if let cached = Self.animatedPreviews.object(forKey: itemID as NSUUID) {
                return Thumbnail(data: cached as Data, isAnimated: true)
            }
            if let gif = ImageDownsampler.animatedGIF(
                from: imageData,
                maxPixel: maxPixel,
                maxFrames: Self.maxAnimatedFrames
            ) {
                Self.animatedPreviews.setObject(gif as NSData, forKey: itemID as NSUUID, cost: gif.count)
                return Thumbnail(data: gif, isAnimated: true)
            }
        }
        if let png = ImageDownsampler.thumbnailPNG(from: imageData, maxPixel: maxPixel) {
            return Thumbnail(data: png, isAnimated: false)
        }
        guard let svg = await SVGThumbnail.png(from: imageData, maxPixel: maxPixel) else { return nil }
        return Thumbnail(data: svg, isAnimated: false)
    }
}
