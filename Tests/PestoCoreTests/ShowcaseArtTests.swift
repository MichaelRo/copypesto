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

    @Test("the basil in sunglasses is a rich 960 by 640 picture in many tones, and the same every time")
    func whenBasilInSunglassesDrawn_thenRichAndDeterministic() throws {
        let image = try decode(ShowcaseArt.basilInSunglasses())
        let again = try decode(ShowcaseArt.basilInSunglasses())

        #expect(image.width == 960 && image.height == 640)
        #expect(distinctColours(image) >= 200)
        #expect(meanDifference(image, again) < 0.05)
    }

    @Test("the jar frames are 640 by 428 and the loop closes: the last step leads back to the first")
    func whenJarFramesDrawn_thenTheyLoop() throws {
        let first = try #require(ShowcaseArt.pestoJarFrame(progress: 0))
        let middle = try #require(ShowcaseArt.pestoJarFrame(progress: 0.5))
        let wrapped = try #require(ShowcaseArt.pestoJarFrame(progress: 1))

        #expect(first.width == 640 && first.height == 428)
        #expect(distinctColours(first) >= 200)
        #expect(meanDifference(first, middle) > 2)
        #expect(meanDifference(first, wrapped) < 0.05)
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        let count = image.width * image.height * 4
        return [UInt8](unsafeUninitializedCapacity: count) { buffer, initialized in
            buffer.initialize(repeating: 0)
            initialized = count
            guard let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
    }

    private func meanDifference(_ first: CGImage, _ second: CGImage) -> Double {
        let left = pixels(first)
        let right = pixels(second)
        let total = zip(left, right).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        return Double(total) / Double(left.count)
    }
}
