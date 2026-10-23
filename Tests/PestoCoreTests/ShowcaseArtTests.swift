// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import PestoCore

@Suite("Showcase art")
struct ShowcaseArtTests {
    private func decode(_ data: Data) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func distinctColours(_ image: CGImage) -> Int {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let pixels = { () -> UnsafeMutablePointer<UInt8>? in
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return context.data?.assumingMemoryBound(to: UInt8.self)
        }() else { return 0 }
        var seen = Set<UInt32>()
        for index in stride(from: 0, to: context.bytesPerRow * image.height, by: 4 * 7) {
            seen.insert(UInt32(pixels[index]) << 16 | UInt32(pixels[index + 1]) << 8 | UInt32(pixels[index + 2]))
        }
        return seen.count
    }

    @Test("each picture decodes as a 480 by 320 image with real detail, not a flat fill")
    func whenDrawn_thenARealPicture() throws {
        for data in [ShowcaseArt.basilLeaves(), ShowcaseArt.pineNuts(), ShowcaseArt.ingredientPalette()] {
            let image = try decode(data)

            #expect(image.width == 480 && image.height == 320)
            #expect(distinctColours(image) >= 4)
        }
    }

    @Test("the pictures are different from each other")
    func whenCompared_thenDistinct() {
        let all = [ShowcaseArt.basilLeaves(), ShowcaseArt.pineNuts(), ShowcaseArt.ingredientPalette()]
        #expect(Set(all).count == 3)
    }

    @Test("drawing is deterministic, so screenshots do not change between runs")
    func whenDrawnTwice_thenIdentical() {
        #expect(ShowcaseArt.pineNuts() == ShowcaseArt.pineNuts())
    }
}
