// SPDX-License-Identifier: MIT
import Foundation
import ImageIO
import PestoCore
import UIKit

/// The frames a card or the detail plays for a GIF, decoded off the main thread from the small GIF the thumbnail
/// service already made (`ImageDownsampler.animatedGIF`), each at most `maxPixel` on its longer side and all of them
/// within `maxBytes`: past that, frames are dropped evenly and their time given to the frame kept.
enum GIFFrames {
    struct Animation {
        let frames: [UIImage]
        let duration: TimeInterval

        var byteCost: Int {
            frames.reduce(0) { $0 + ($1.cgImage.map { $0.bytesPerRow * $0.height } ?? 0) }
        }
    }

    struct Budget: Equatable {
        let maxPixel: Int
        let maxBytes: Int

        static let card = Budget(maxPixel: 360, maxBytes: 12 * 1024 * 1024)
        static let detail = Budget(maxPixel: 720, maxBytes: 48 * 1024 * 1024)
    }

    /// How many of `total` frames of `frameBytes` each fit the budget, and the step between the frames kept.
    static func plan(total: Int, frameBytes: Int, maxBytes: Int) -> (count: Int, step: Int) {
        guard total > 0, frameBytes > 0 else { return (0, 1) }
        let fitting = max(1, min(total, maxBytes / frameBytes))
        let step = max(1, Int((Double(total) / Double(fitting)).rounded(.up)))
        return (Int((Double(total) / Double(step)).rounded(.up)), step)
    }

    @concurrent
    static func decode(_ data: Data, budget: Budget) async -> Animation? {
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else { return nil }
        let total = CGImageSourceGetCount(source)
        guard total > 1 else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: budget.maxPixel
        ] as CFDictionary
        guard let first = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let plan = plan(total: total, frameBytes: first.bytesPerRow * first.height, maxBytes: budget.maxBytes)
        guard plan.count > 1 else { return nil }
        var frames: [UIImage] = []
        var duration: TimeInterval = 0
        for index in stride(from: 0, to: total, by: plan.step) {
            let frame = index == 0 ? first : CGImageSourceCreateThumbnailAtIndex(source, index, options)
            guard let frame else { continue }
            let image = UIImage(cgImage: frame)
            frames.append(image.preparingForDisplay() ?? image)
            duration += (index..<min(index + plan.step, total)).reduce(0) { $0 + delay(source, at: $1) }
        }
        return frames.count > 1 ? Animation(frames: frames, duration: duration) : nil
    }

    private static func delay(_ source: CGImageSource, at index: Int) -> TimeInterval {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let raw = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
        return AnimatedImagePlayback.normalizedDuration(raw)
    }
}

/// Whether a picture plays: an animated one, on screen, not covered, and not under Reduce Motion (first frame then).
enum CardAnimation {
    static func plays(isAnimated: Bool, isOnScreen: Bool, isConcealed: Bool, reduceMotion: Bool) -> Bool {
        isAnimated && isOnScreen && !isConcealed && !reduceMotion
    }
}
