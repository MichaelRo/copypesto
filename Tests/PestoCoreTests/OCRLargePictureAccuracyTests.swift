// SPDX-License-Identifier: MIT
import AppKit
import ImageIO
import Testing
import Vision
@testable import PestoCore

/// Text recognition on a picture over 24 MP reads a scaled copy (ADR 0006). This renders small text on a canvas over
/// the limit and compares what the scaled read finds with a read of the same picture at full size.
@Suite(
    "Text recognition on pictures over the pixel limit",
    .enabled(if: VisionAvailability.canRecognizeText, "text recognition needs a real Mac")
)
struct OCRLargePictureAccuracyTests {
    private static let words = [
        "invoice", "payment", "balance", "account", "reference", "quarterly", "meeting", "agenda", "deadline",
        "project", "customer", "shipping", "address", "confirm", "password", "network", "database", "server",
        "release", "version", "compile", "deploy", "status", "report", "budget", "contract", "support", "review",
        "design", "feature", "update", "backup", "restore", "encrypt", "history", "pasteboard", "shortcut", "preview"
    ]

    private static let rowFontSizes: [CGFloat] = [20, 26, 32, 44]

    /// Rows of words in black on white, a block per font size, on a canvas of `width` x `height` pixels.
    private static func render(width: Int, height: Int) -> (png: Data, expected: [CGFloat: [String]])? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        var expected: [CGFloat: [String]] = [:]
        var next = 0
        let band = CGFloat(height) / CGFloat(rowFontSizes.count)
        let columnWidth: CGFloat = 900
        for (index, size) in rowFontSizes.enumerated() {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.black
            ]
            let top = CGFloat(height) - CGFloat(index) * band - 40
            var columnX: CGFloat = 40
            while columnX + columnWidth < CGFloat(width) - 40 {
                var y = top
                var line = 0
                while y > top - band + size * 4 {
                    if line % 7 == 6 {
                        y -= size * 1.6
                        line += 1
                        continue
                    }
                    var x = columnX
                    while true {
                        let word = words[next % words.count] + String(next % 7 + 2)
                        next += 1
                        let wordWidth = (word as NSString).size(withAttributes: attributes).width
                        if x + wordWidth > columnX + columnWidth { break }
                        (word as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
                        expected[size, default: []].append(word)
                        x += wordWidth + size * 0.5
                    }
                    y -= size * 1.6
                    line += 1
                }
                columnX += columnWidth + 120
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return (png, expected)
    }

    private static func fullSizeRead(_ png: Data) -> String {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    private static func recall(of words: [String], in text: String) -> Double {
        let found = Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        guard !words.isEmpty else { return 1 }
        return Double(words.count { found.contains($0.lowercased()) }) / Double(words.count)
    }

    @Test("a 33 MP picture read from its scaled copy keeps most of what a full-size read finds")
    func whenThePictureIsOverTheLimit_thenTheScaledReadKeepsMostOfTheFullRead() async throws {
        let (png, expected) = try #require(Self.render(width: 7680, height: 4320))
        #expect(7680 * 4320 > ImageDownsampler.maxDecodedPixels)
        let words = Self.rowFontSizes.flatMap { expected[$0] ?? [] }

        let full = Self.recall(of: words, in: Self.fullSizeRead(png))
        let scaled = try Self.recall(of: words, in: #require(await OCRService().recognize(imageData: png)))

        #expect(full > 0.02, "the full-size read found almost nothing, so the comparison proves nothing")
        #expect(scaled >= 0.5 * full, "the scaled read finds \(scaled) against \(full) at full size (ADR 0006)")
    }
}
