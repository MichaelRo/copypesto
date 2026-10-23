// SPDX-License-Identifier: MIT
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

/// 64-bit average-hash (pHash) for image dedupe.
///
/// We don't need cryptographic robustness; we need "two screenshots taken 500 ms apart
/// hash the same". Average-hash is the cheapest perceptual primitive: downscale to 8×8 grayscale,
/// compute the mean, bit-set per pixel for above/below mean.
public enum PerceptualHasher {
    /// Returns a 64-bit hash rendered as a 16-char lowercase hex string, or nil if the data isn't a decodable image.
    public static func hash(imageData: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            return nil
        }
        return hash(imageSource: source)
    }

    static func hash(imageSource source: CGImageSource) -> String? {
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 8
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            return nil
        }
        return hash(cgImage: thumb)
    }

    static func hash(cgImage image: CGImage) -> String? {
        // Render to a grayscale 8×8 buffer.
        let width = 8
        let height = 8
        let bytesPerRow = width
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = pixels.withUnsafeMutableBytes({ ptr -> CGContext? in
            CGContext(
                data: ptr.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        }) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let mean = pixels.reduce(0) { $0 + Int($1) } / pixels.count
        var bits: UInt64 = 0
        for (i, pixel) in pixels.enumerated() where Int(pixel) >= mean {
            bits |= 1 << (63 - i)
        }
        return String(format: "%016llx", bits)
    }

    /// Number of differing bits between two hex-encoded pHashes.
    /// Range 0…64. Values ≤5 indicate visual similarity (empirically tuned).
    public static func hammingDistance(_ a: String, _ b: String) -> Int? {
        guard let lhs = UInt64(a, radix: 16),
              let rhs = UInt64(b, radix: 16) else { return nil }
        return (lhs ^ rhs).nonzeroBitCount
    }

    /// The coarse hash only nominates candidates: at 8×8 it cannot tell two screenshots of one window apart when a
    /// few words differ. A candidate is a duplicate only if the decoded pixels are identical.
    public static let similarityThreshold: Int = 5

    /// Most lookalikes whose pixels are decoded for one new picture. Each costs a decrypt and a full decode, so a
    /// run of near-identical screenshots must not make one more copy pay for fifty of them; a duplicate older than
    /// the newest few is stored again, which costs nothing but a card (ADR 0006).
    public static let maxDecodedCandidates = 5

    /// The ids, newest first as given, whose coarse hash is within the similarity threshold of `candidate`.
    public static func nominees<ID>(
        for candidate: String,
        among existing: [(id: ID, hash: String?)],
        limit: Int = maxDecodedCandidates
    )
    -> [ID] {
        let near = existing.lazy.filter { entry in
            guard let hash = entry.hash else { return false }
            return (hammingDistance(candidate, hash) ?? .max) <= similarityThreshold
        }
        return near.prefix(limit).map(\.id)
    }

    /// Largest image whose pixels are decoded for comparison; anything bigger is never treated as a duplicate.
    private static let maxDigestPixels = ImageDownsampler.maxDecodedPixels

    /// SHA-256 of the decoded RGBA pixels (sRGB), so the same picture in another lossless encoding matches.
    /// nil when the data is not a decodable image or is too large to decode cheaply.
    public static func pixelDigest(imageData: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width * image.height <= maxDigestPixels,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let bytesPerRow = image.width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { return nil }
        return Data(SHA256.hash(data: pixels))
    }
}
