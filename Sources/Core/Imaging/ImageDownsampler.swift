// SPDX-License-Identifier: MIT
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageDownsampler {
    /// The most pixels anything decodes at full size: a full 6K screen (6016 x 3384). A decoded picture costs 4 bytes
    /// a pixel and the readers on top of it (text recognition, the duplicate check) roughly 8 more, which holds one
    /// decode near 300 MB; a flat 400-megapixel PNG is 7 MB on disk and took 3.9 GB. See ADR 0006.
    static let maxDecodedPixels = 24 * 1_048_576

    /// The first image of `source`, decoded at full size, or scaled down to `maxDecodedPixels` when it is larger.
    static func boundedImage(from source: CGImageSource) -> CGImage? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width * height > maxDecodedPixels else { return CGImageSourceCreateImageAtIndex(source, 0, nil) }
        let scale = (Double(maxDecodedPixels) / Double(width * height)).squareRoot()
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(Double(max(width, height)) * scale)
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Decodes straight to the target size, never materialising the full-resolution bitmap the way `NSImage(data:)`
    /// does.
    public static func thumbnailPNG(from data: Data, maxPixel: Int) -> Data? {
        if data.starts(with: Data("%PDF".utf8)) { return pdfThumbnailPNG(from: data, maxPixel: maxPixel) }
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        let png = UTType.png.identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(output, png, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    /// The first page of a PDF, scaled to fit `maxPixel`. ImageIO does not read PDF, so the page is drawn directly.
    private static func pdfThumbnailPNG(from data: Data, maxPixel: Int) -> Data? {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider),
              let page = document.page(at: 1) else { return nil }
        let box = page.getBoxRect(.cropBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let scale = CGFloat(maxPixel) / max(box.width, box.height)
        let width = max(1, Int((box.width * scale).rounded()))
        let height = max(1, Int((box.height * scale).rounded()))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.minX, y: -box.minY)
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { return nil }
        let output = NSMutableData()
        let png = UTType.png.identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(output, png, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    /// A smaller GIF for showing on a card: every frame scaled to `maxPixel`, and at most `maxFrames` of them (frames
    /// are dropped evenly and their time added to the frame kept, so it runs as long as the original). The original is
    /// never touched; this is only what the shelf plays. Animated WebP and PNG, which is what sites such as GIPHY send
    /// as their link picture, come out as GIFs because `NSImageView` only plays those. Nil for anything that is not
    /// a GIF or has a single frame.
    public static func animatedGIF(from data: Data, maxPixel: Int, maxFrames: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else { return nil }
        let total = CGImageSourceGetCount(source)
        let isGIF = CGImageSourceGetType(source) as String? == UTType.gif.identifier
        guard total > 0, isGIF || total > 1 else { return nil }
        let step = max(1, Int((Double(total) / Double(max(1, maxFrames))).rounded(.up)))
        let kept = Array(stride(from: 0, to: total, by: step))

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.gif.identifier as CFString,
            kept.count,
            nil
        ) else { return nil }
        CGImageDestinationSetProperties(
            destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
        )
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        let thumbnailOptions = options as CFDictionary
        var written = 0
        for index in kept {
            // A frame that will not decode is skipped; the rest still play.
            guard let frame = CGImageSourceCreateThumbnailAtIndex(source, index, thumbnailOptions) else { continue }
            let delay = (index..<min(index + step, total)).reduce(0.0) { $0 + frameDelay(source, index: $1) }
            CGImageDestinationAddImage(
                destination, frame,
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: max(0.02, delay)]] as CFDictionary
            )
            written += 1
        }
        return written > 0 && CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    private struct DelayKeys {
        let dictionary: CFString
        let unclamped: CFString
        let clamped: CFString
    }

    private static var delayKeys: [DelayKeys] {
        [
            DelayKeys(
                dictionary: kCGImagePropertyGIFDictionary,
                unclamped: kCGImagePropertyGIFUnclampedDelayTime, clamped: kCGImagePropertyGIFDelayTime
            ),
            DelayKeys(
                dictionary: kCGImagePropertyWebPDictionary,
                unclamped: kCGImagePropertyWebPUnclampedDelayTime, clamped: kCGImagePropertyWebPDelayTime
            ),
            DelayKeys(
                dictionary: kCGImagePropertyPNGDictionary,
                unclamped: kCGImagePropertyAPNGUnclampedDelayTime, clamped: kCGImagePropertyAPNGDelayTime
            )
        ]
    }

    private static func frameDelay(_ source: CGImageSource, index: Int) -> Double {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        for keys in delayKeys {
            guard let dictionary = properties?[keys.dictionary] as? [CFString: Any] else { continue }
            let unclamped = dictionary[keys.unclamped] as? Double ?? 0
            if unclamped > 0 { return unclamped }
            if let delay = dictionary[keys.clamped] as? Double { return delay }
        }
        return 0.1
    }
}
