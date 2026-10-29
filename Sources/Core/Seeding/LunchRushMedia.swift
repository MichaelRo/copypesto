// SPDX-License-Identifier: MIT
import AVFoundation
import CoreGraphics
import CoreText
import Foundation
import ImageIO

/// The GIF, the PDF and the short video of the Lunch Rush shelf, drawn in code by `ShowcaseArt`, so the demo shows
/// every
/// kind of clip without shipping or borrowing a file. The PDF and the video are written to a temporary folder because
/// Pesto keeps those as file clips.
enum LunchRushMedia {
    private static let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pesto-lunch-rush")

    /// Made once: the seed is read more than once per run, and two writers on one file fail.
    static let pestoGIF = makeGIF()
    static let recipePDF = makePDF()
    static let jarVideo = makeVideo()

    /// Twelve frames of a jar of pesto being stirred, looping.
    private static func makeGIF() -> Data {
        let frames = 12
        let output = NSMutableData()
        let gifType = "com.compuserve.gif" as CFString
        guard let destination = CGImageDestinationCreateWithData(output, gifType, frames, nil) else { return Data() }
        CGImageDestinationSetProperties(
            destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
        )
        for step in 0..<frames {
            guard let frame = ShowcaseArt.pestoJarFrame(progress: Double(step) / Double(frames)) else { return Data() }
            CGImageDestinationAddImage(
                destination, frame,
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.08]] as CFDictionary
            )
        }
        return CGImageDestinationFinalize(destination) ? output as Data : Data()
    }

    /// One page: a recipe a person might keep in a folder of its own, as a PDF file clip.
    private static func makePDF() -> URL? {
        let url = folder.appendingPathComponent("grandmas-recipe-final-FINAL-v3.pdf")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return nil }
        context.beginPDFPage(nil)
        context.setFillColor(ShowcaseArt.color(hex: BrandPalette.parmesan))
        context.fill(box)
        context.setFillColor(ShowcaseArt.color(hex: BrandPalette.accentLight))
        context.fill(CGRect(x: 0, y: 700, width: 612, height: 92))
        ShowcaseArt.leftText(
            context, "Grandma\u{2019}s pesto", fontName: "HelveticaNeue-Bold", size: 44, hex: BrandPalette.garlic,
            at: CGPoint(x: 56, y: 730)
        )
        ShowcaseArt.leftText(
            context, "FINAL v3 (v2 was better)", fontName: "HelveticaNeue-Italic", size: 20, hex: BrandPalette.stone,
            at: CGPoint(x: 56, y: 660)
        )
        var baseline: CGFloat = 590
        for line in recipeLines {
            ShowcaseArt.leftText(
                context, line, fontName: "HelveticaNeue", size: 26, hex: BrandPalette.mortar, at: CGPoint(x: 56, y: baseline)
            )
            baseline -= 56
        }
        context.setStrokeColor(ShowcaseArt.color(hex: BrandPalette.goldFill))
        context.setLineWidth(3)
        context.move(to: CGPoint(x: 56, y: 640))
        context.addLine(to: CGPoint(x: 556, y: 640))
        context.strokePath()
        context.endPDFPage()
        context.closePDF()
        return url
    }

    private static let recipeLines = [
        "2 cups basil, more",
        "1 cup parmesan, the real one",
        "1/2 cup pine nuts, count them",
        "1/2 cup olive oil, the good one",
        "2 cloves garlic, make it three",
        "A pinch of salt, her pinch"
    ]

    /// Two seconds of the jar being stirred, as an H.264 file.
    private static func makeVideo() -> URL? {
        let url = folder.appendingPathComponent("pesto-spoon.mp4")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }
        let size = ShowcaseArt.jarFrameSize
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height)
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height)
        ])
        writer.add(input)
        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)
        let total = 48
        for index in 0..<total {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.005)
            }
            guard let pool = adaptor.pixelBufferPool else { return nil }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer,
                  let picture = ShowcaseArt.pestoJarFrame(progress: Double(index) / Double(total)) else { return nil }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
            ) {
                context.draw(picture, in: CGRect(origin: .zero, size: size))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 24))
        }
        input.markAsFinished()
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        finished.wait()
        return writer.status == .completed ? url : nil
    }
}
