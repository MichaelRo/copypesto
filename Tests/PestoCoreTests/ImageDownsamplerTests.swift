// SPDX-License-Identifier: MIT
import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PestoCore

@Suite("ImageDownsampler")
struct ImageDownsamplerTests {
    private func png(width: Int, height: Int) throws -> Data {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    private func size(of data: Data) throws -> (width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (props[kCGImagePropertyPixelWidth] as? Int ?? 0, props[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    @Test("a PDF page is rendered to a thumbnail that fits, keeping the page's aspect ratio")
    func whenPDF_thenFirstPageRendered() throws {
        var box = CGRect(x: 0, y: 0, width: 600, height: 300)
        let output = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: output))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1))
        context.fill(box)
        context.endPDFPage()
        context.closePDF()

        let thumbnail = try #require(ImageDownsampler.thumbnailPNG(from: output as Data, maxPixel: 200))

        let dimensions = try size(of: thumbnail)
        #expect(dimensions.width == 200)
        #expect(dimensions.height == 100)
    }

    @Test("bytes that are neither an image nor a PDF give no thumbnail")
    func whenGarbage_thenNil() {
        #expect(ImageDownsampler.thumbnailPNG(from: Data("not an image".utf8), maxPixel: 100) == nil)
    }

    @Test("a large image is scaled so its longest side fits, keeping the aspect ratio")
    func whenLargeImage_thenScaledDownKeepingRatio() throws {
        let thumbnail = try #require(ImageDownsampler.thumbnailPNG(from: png(width: 2000, height: 1000), maxPixel: 400))

        let dimensions = try size(of: thumbnail)

        #expect(dimensions.width == 400)
        #expect(dimensions.height == 200)
    }

    @Test("the thumbnail is much smaller than a large original")
    func whenLargeImage_thenSmallerBytes() throws {
        let original = try png(width: 3000, height: 2000)

        let thumbnail = try #require(ImageDownsampler.thumbnailPNG(from: original, maxPixel: 300))

        #expect(thumbnail.count < original.count)
    }

    @Test("data that is not an image gives nil, not a crash")
    func whenNotAnImage_thenNil() {
        #expect(ImageDownsampler.thumbnailPNG(from: Data("nope".utf8), maxPixel: 100) == nil)
    }
}

@Suite("Animated GIF downsizing")
struct AnimatedGIFDownsizingTests {
    /// A GIF of `frames` frames, `side` pixels square, each `delay` seconds long.
    private func gif(frames: Int, side: Int, delay: Double = 0.1) throws -> Data {
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            output,
            UTType.gif.identifier as CFString,
            frames,
            nil
        ))
        CGImageDestinationSetProperties(
            destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
        )
        for index in 0..<frames {
            let context = try #require(CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.setFillColor(CGColor(red: Double(index % 255) / 255, green: 0.4, blue: 0.7, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            try CGImageDestinationAddImage(
                destination, #require(context.makeImage()),
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary
            )
        }
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func frameCount(_ data: Data) -> Int {
        CGImageSourceCreateWithData(data as CFData, nil).map(CGImageSourceGetCount) ?? 0
    }

    private func size(_ data: Data) -> (Int, Int) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return (0, 0) }
        return (props[kCGImagePropertyPixelWidth] as? Int ?? 0, props[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    private func duration(_ data: Data) -> Double {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return 0 }
        return (0..<CGImageSourceGetCount(source)).reduce(0.0) { total, index in
            let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            return total +
                (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double ??
                    gif?[kCGImagePropertyGIFDelayTime] as? Double ?? 0)
        }
    }

    @Test("a large GIF is scaled down and stays animated with every frame")
    func whenLarge_thenScaledAndStillAnimated() throws {
        let original = try gif(frames: 12, side: 400)
        let small = try #require(ImageDownsampler.animatedGIF(from: original, maxPixel: 100, maxFrames: 60))

        let (width, height) = size(small)
        #expect(max(width, height) <= 100 && min(width, height) > 0)
        #expect(frameCount(small) == 12)
        #expect(small.count < original.count)
    }

    @Test("a long GIF is thinned to the frame cap and keeps its total running time")
    func whenTooManyFrames_thenThinnedKeepingDuration() throws {
        let original = try gif(frames: 200, side: 64, delay: 0.05)
        let small = try #require(ImageDownsampler.animatedGIF(from: original, maxPixel: 64, maxFrames: 50))

        #expect(frameCount(small) <= 50)
        #expect(abs(duration(small) - duration(original)) < 1.0, "\(duration(small)) vs \(duration(original))")
    }

    @Test("a GIF already small enough keeps its frames")
    func whenSmall_thenUnchangedFrames() throws {
        let original = try gif(frames: 5, side: 32)
        let result = try #require(ImageDownsampler.animatedGIF(from: original, maxPixel: 480, maxFrames: 60))
        #expect(frameCount(result) == 5)
        #expect(size(result).0 == 32)
    }

    @Test("something that is not a GIF, or not an image, gives nothing")
    func whenNotAGIF_thenNil() {
        #expect(ImageDownsampler.animatedGIF(from: Data("hello".utf8), maxPixel: 100, maxFrames: 10) == nil)
    }

    private func animatedPNG(frames: Int, side: Int, delay: Double) throws -> Data {
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, frames, nil
        ))
        CGImageDestinationSetProperties(
            destination, [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]] as CFDictionary
        )
        for index in 0..<frames {
            let context = try #require(CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.setFillColor(CGColor(red: Double(index) / Double(frames), green: 0.4, blue: 0.7, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            try CGImageDestinationAddImage(
                destination, #require(context.makeImage()),
                [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: delay]] as CFDictionary
            )
        }
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    @Test("a link picture that is animated but not a GIF (WebP, APNG) becomes a playing GIF")
    func whenAnimatedButNotGIF_thenGIFWithEveryFrame() throws {
        let original = try animatedPNG(frames: 8, side: 120, delay: 0.1)
        let result = try #require(ImageDownsampler.animatedGIF(from: original, maxPixel: 60, maxFrames: 60))

        #expect(result.isGIF)
        #expect(frameCount(result) == 8)
        #expect(abs(duration(result) - 0.8) < 0.1, "\(duration(result))")
    }

    @Test("a still picture is not turned into a GIF")
    func whenStillPicture_thenNil() throws {
        let still = try animatedPNG(frames: 1, side: 40, delay: 0.1)
        #expect(ImageDownsampler.animatedGIF(from: still, maxPixel: 60, maxFrames: 60) == nil)
    }
}
