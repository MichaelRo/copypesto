// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PestoCore

@Suite("A picture scaled down from its file")
struct ImageDownsamplerFileTests {
    @Test("a large picture comes out as a PNG no longer than the limit on its longer side")
    func whenScaledFromAFile_thenTheLongerSideIsBounded() throws {
        let context = try #require(CGContext(
            data: nil, width: 3000, height: 1000, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 3000, height: 1000))
        let image = try #require(context.makeImage())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pesto-scale-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))

        let png = try #require(ImageDownsampler.thumbnailPNG(contentsOf: url, maxPixel: 600))
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])

        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 600)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 200)
        #expect(ImageDownsampler.thumbnailPNG(
            contentsOf: url.deletingLastPathComponent().appendingPathComponent("missing.png"), maxPixel: 600
        ) == nil)
    }
}
