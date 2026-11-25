// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation
import Testing
import UIKit

/// A rendered view for a test: its pixels to compare, and a PNG beside the repository for a person to look at. A CI
/// simulator sometimes fails to encode a PNG ("zlib error, No IDATs written") and hands back images whose data
/// provider is empty, so the pixels are drawn into a buffer the test owns and the picture is only best effort.
enum RenderedImage {
    static func pixels(_ image: UIImage) throws -> Data {
        let cgImage = try #require(image.cgImage, "the renderer drew no bitmap")
        let width = cgImage.width
        let height = cgImage.height
        try #require(width > 0 && height > 0, "the bitmap is empty")
        let bytesPerRow = width * 4
        var buffer = Data(count: bytesPerRow * height)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        try #require(drawn, "no bitmap context for the pixels")
        return buffer
    }

    static func saveForReview(_ image: UIImage, to url: URL) {
        guard let png = image.pngData() else { return }
        try? png.write(to: url)
    }
}
