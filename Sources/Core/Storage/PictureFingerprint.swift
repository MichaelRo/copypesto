// SPDX-License-Identifier: MIT
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import Synchronization
import UniformTypeIdentifiers

/// A finer look at a picture than the 8×8 hash, cheap enough to take at copy time (ADR 0077). It can only show that two
/// pictures differ, and only when both are PNG files read the same way: ImageIO scales the same pixels from another
/// container, interlacing or bit depth further apart than a few changed words are.
public struct PictureFingerprint: Codable, Equatable, Sendable {
    /// What decides how ImageIO scales the file, the system version included.
    let reading: Data
    /// SHA-256 of the picture scaled to at most `maxSide`.
    let pixels: Data

    static let maxSide = 512

    /// nil for anything but a PNG, and for a picture too large to be compared by its pixels at all. A lossy copy also
    /// counts as the same picture when it is merely close, which a fingerprint cannot tell, and a TIFF may be tiled or
    /// planar, which scales the same pixels differently and is not all announced.
    init?(imageSource source: CGImageSource) {
        let uncached = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let type = CGImageSourceGetType(source) as String?, type == UTType.png.identifier,
              let image = CGImageSourceCreateImageAtIndex(source, 0, uncached),
              image.width * image.height <= ImageDownsampler.maxDecodedPixels else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceThumbnailMaxPixelSize: Self.maxSide
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let pixels = PerceptualHasher.sRGBDigest(of: thumbnail) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, uncached) as? [CFString: Any]
        let layout = [
            ProcessInfo.processInfo.operatingSystemVersionString, type,
            "\(image.width)x\(image.height)", "\(image.bitsPerComponent)/\(image.bitsPerPixel)",
            "\(image.bitmapInfo.rawValue)", "\(image.colorSpace?.model.rawValue ?? -1)",
            "\(properties?[kCGImagePropertyOrientation] as? Int ?? 1)",
            "\(Self.interlaceType(of: properties))"
        ].joined(separator: "|")
        var reading = SHA256()
        reading.update(data: Data(layout.utf8))
        if let profile = image.colorSpace?.copyICCData() { reading.update(data: profile as Data) }
        self.reading = Data(reading.finalize())
        self.pixels = pixels
    }

    init?(imageData: Data) {
        guard let source = Self.uncachedSource(imageData) else { return nil }
        self.init(imageSource: source)
    }

    /// The 8×8 hash and the fingerprint of one picture. Each is a pass over the whole file, so the two run side by side
    /// and a copy waits for the slower one. An interlaced PNG runs them in turn, because two at once hold its pixels
    /// twice. The caller is blocked, and no thread of Swift's pool is needed (ADR 0077).
    static func withCoarseHash(imageData: Data) -> (hash: String?, fingerprint: PictureFingerprint?) {
        let properties = uncachedSource(imageData).flatMap {
            CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any]
        }
        guard interlaceType(of: properties) == 0 else {
            return (PerceptualHasher.hash(imageData: imageData), PictureFingerprint(imageData: imageData))
        }
        let hash = Mutex<String?>(nil)
        let fingerprint = Mutex<PictureFingerprint?>(nil)
        DispatchQueue.concurrentPerform(iterations: 2) { pass in
            if pass == 0 {
                let value = PerceptualHasher.hash(imageData: imageData)
                hash.withLock { $0 = value }
            } else {
                let value = PictureFingerprint(imageData: imageData)
                fingerprint.withLock { $0 = value }
            }
        }
        return (hash.withLock { $0 }, fingerprint.withLock { $0 })
    }

    private static func uncachedSource(_ data: Data) -> CGImageSource? {
        CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
    }

    private static func interlaceType(of properties: [CFString: Any]?) -> Int {
        (properties?[kCGImagePropertyPNGDictionary] as? [CFString: Any])?[kCGImagePropertyPNGInterlaceType] as? Int ?? 0
    }

    /// True only when the two cannot hold the same pixels. False says nothing: compare the pixels.
    func rulesOut(_ other: PictureFingerprint) -> Bool {
        reading == other.reading && pixels != other.pixels
    }
}
