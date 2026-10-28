// SPDX-License-Identifier: MIT
import AVFoundation
import CoreGraphics
import CoreText
import Foundation
import ImageIO

/// The GIF, the PDF and the short video of the Lunch Rush shelf, drawn in code from `ShowcaseArt`, so the demo shows
/// every
/// kind of clip without shipping or borrowing a file. The PDF and the video are written to a temporary folder because
/// Pesto keeps those as file clips.
enum LunchRushMedia {
    private static let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pesto-lunch-rush")

    /// Made once: the seed is read more than once per run, and two writers on one file fail.
    static let pestoGIF = makeGIF()
    static let recipePDF = makePDF()
    static let bowlVideo = makeVideo()

    private static func bowlImage() -> CGImage? {
        guard let source = CGImageSourceCreateWithData(ShowcaseArt.pestoBowl() as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Eight frames of the bowl with a small basil leaf circling it.
    private static func makeGIF() -> Data {
        let frames = 8
        let output = NSMutableData()
        let gifType = "com.compuserve.gif" as CFString
        guard let bowl = bowlImage(),
              let destination = CGImageDestinationCreateWithData(output, gifType, frames, nil) else { return Data() }
        CGImageDestinationSetProperties(
            destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
        )
        for step in 0..<frames {
            guard let frame = frame(
                of: bowl,
                progress: Double(step) / Double(frames),
                size: CGSize(width: 320, height: 214)
            ) else { return Data() }
            CGImageDestinationAddImage(
                destination, frame,
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.12]] as CFDictionary
            )
        }
        return CGImageDestinationFinalize(destination) ? output as Data : Data()
    }

    private static func frame(of bowl: CGImage, progress: Double, size: CGSize) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let zoom = 1 + 0.06 * sin(progress * 2 * .pi)
        let drawn = CGSize(width: size.width * zoom, height: size.height * zoom)
        context.draw(bowl, in: CGRect(
            x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2,
            width: drawn.width, height: drawn.height
        ))
        let angle = progress * 2 * .pi
        let center = CGPoint(x: size.width / 2 + cos(angle) * 105, y: size.height / 2 + sin(angle) * 70)
        context.setFillColor(CGColor(srgbRed: 0.43, green: 0.75, blue: 0.52, alpha: 1))
        context.fillEllipse(in: CGRect(x: center.x - 14, y: center.y - 8, width: 28, height: 16))
        return context.makeImage()
    }

    /// One page: a recipe a person might keep, as a PDF file clip.
    private static func makePDF() -> URL? {
        let url = folder.appendingPathComponent("pesto-for-four.pdf")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return nil }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(srgbRed: 0.965, green: 0.937, blue: 0.851, alpha: 1))
        context.fill(box)
        let lines = ["Pesto for four"] + LunchRushSeed.ingredients.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        var baseline: CGFloat = 700
        for (index, text) in lines.enumerated() {
            let size: CGFloat = index == 0 ? 40 : 24
            let fontName = index == 0 ? "HelveticaNeue-Bold" : "HelveticaNeue"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: CTFontCreateWithName(fontName as CFString, size, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                    CGColor(srgbRed: 0.17, green: 0.18, blue: 0.16, alpha: 1)
            ]
            context.textPosition = CGPoint(x: 72, y: baseline)
            CTLineDraw(
                CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)),
                context
            )
            baseline -= size + 22
        }
        context.endPDFPage()
        context.closePDF()
        return url
    }

    /// Two seconds of the bowl, slowly zooming, as an H.264 file.
    private static func makeVideo() -> URL? {
        let url = folder.appendingPathComponent("pesto-spoon.mp4")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        guard let bowl = bowlImage(),
              let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }
        let size = CGSize(width: 480, height: 320)
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
                  let picture = frame(of: bowl, progress: Double(index) / Double(total), size: size) else { return nil }
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
