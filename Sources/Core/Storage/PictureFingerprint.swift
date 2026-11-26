// SPDX-License-Identifier: MIT
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A finer look at a picture than the 8×8 hash, cheap enough to take at copy time (ADR 0077). It can only show that two
/// pictures differ, and only when both files are read the same way: ImageIO scales the same pixels from another
/// container, interlacing or bit depth further apart than a few changed words are.
public struct PictureFingerprint: Codable, Equatable, Sendable {
    /// What decides how ImageIO scales the file, the system version included.
    let reading: Data
    /// SHA-256 of the picture scaled to at most `maxSide`.
    let pixels: Data

    static let maxSide = 512

    /// The containers whose same pixels may count as one clip only when they match exactly. A lossy copy also counts
    /// when it is merely close, which a fingerprint cannot tell.
    private static let losslessTypes = [UTType.png.identifier, UTType.tiff.identifier]

    /// nil for a lossy or unknown container, and for a picture too large to be compared by its pixels at all.
    init?(imageSource source: CGImageSource) {
        let uncached = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let type = CGImageSourceGetType(source) as String?, Self.losslessTypes.contains(type),
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
        let png = properties?[kCGImagePropertyPNGDictionary] as? [CFString: Any]
        let layout = [
            ProcessInfo.processInfo.operatingSystemVersionString, type,
            "\(image.width)x\(image.height)", "\(image.bitsPerComponent)/\(image.bitsPerPixel)",
            "\(image.bitmapInfo.rawValue)", "\(image.colorSpace?.model.rawValue ?? -1)",
            "\(properties?[kCGImagePropertyOrientation] as? Int ?? 1)",
            "\(png?[kCGImagePropertyPNGInterlaceType] as? Int ?? 0)"
        ].joined(separator: "|")
        var reading = SHA256()
        reading.update(data: Data(layout.utf8))
        if let profile = image.colorSpace?.copyICCData() { reading.update(data: profile as Data) }
        self.reading = Data(reading.finalize())
        self.pixels = pixels
    }

    /// True only when the two cannot hold the same pixels. False says nothing: compare the pixels.
    func rulesOut(_ other: PictureFingerprint) -> Bool {
        reading == other.reading && pixels != other.pixels
    }
}
