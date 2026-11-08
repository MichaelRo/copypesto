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

    private nonisolated(unsafe) static let stillPreviews: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 32
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()

    public nonisolated static func prewarm(id: UUID, imageData: Data, maxPixel: Int) {
        let key = "\(id.uuidString):\(maxPixel)" as NSString
        guard stillPreviews.object(forKey: key) == nil, !imageData.isGIF,
              let png = ImageDownsampler.thumbnailPNG(from: imageData, maxPixel: maxPixel) else { return }
        stillPreviews.setObject(png as NSData, forKey: key, cost: png.count)
    }

    public nonisolated static func invalidate(id: UUID) {
        animatedPreviews.removeObject(forKey: id as NSUUID)
        for maxPixel in [480, 600, 768, 1024] {
            let cacheKey: NSString = "\(id.uuidString):\(maxPixel)" as NSString
            stillPreviews.removeObject(forKey: cacheKey)
        }
    }

    public func thumbnail(for itemID: UUID, maxPixel: Int) async -> Thumbnail? {
        let stillKey = "\(itemID.uuidString):\(maxPixel)" as NSString
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == itemID })
        descriptor.fetchLimit = 1
        guard let blob = (try? modelContext.fetch(descriptor))?.first?.blob else { return nil }

        let isMimeAnimated = blob.mimeType == "com.compuserve.gif" || blob.mimeType == "public.gif"
        if !isMimeAnimated, let cached = Self.stillPreviews.object(forKey: stillKey) {
            return Thumbnail(data: cached as Data, isAnimated: false)
        }
        guard let imageData = blob.decryptedData() else { return nil }
        let isAnimated = isMimeAnimated || imageData.isGIF
        if isAnimated {
            Self.stillPreviews.removeObject(forKey: stillKey)
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
            Self.stillPreviews.setObject(png as NSData, forKey: stillKey, cost: png.count)
            return Thumbnail(data: png, isAnimated: false)
        }
        guard let svg = await SVGThumbnail.png(from: imageData, maxPixel: maxPixel) else { return nil }
        return Thumbnail(data: svg, isAnimated: false)
    }
}
