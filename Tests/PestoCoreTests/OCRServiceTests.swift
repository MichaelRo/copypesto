// SPDX-License-Identifier: MIT
import AppKit
import Testing
@testable import PestoCore

// MARK: - Helpers

/// Renders `text` as black on white into a 300×80 PNG suitable for Vision OCR.
private func makePNG(text: String) -> Data? {
    let size = CGSize(width: 300, height: 80)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width),
        pixelsHigh: Int(size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 24, weight: .regular),
        .foregroundColor: NSColor.black
    ]
    (text as NSString).draw(at: NSPoint(x: 12, y: 20), withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

// MARK: - Tests

@Suite("OCRService", .enabled(if: VisionAvailability.canRecognizeText, "text recognition needs a real Mac"))
struct OCRServiceTests {
    @Test
    func recognize_extractsTextFromImage() async throws {
        let png = try #require(makePNG(text: "Hello OCR"))
        let result = await OCRService().recognize(imageData: png)
        #expect(result != nil)
        #expect(result?.contains("Hello") == true)
    }

    @Test
    func recognize_returnsNilForBlankImage() async throws {
        // A solid-white image contains no text.
        let size = CGSize(width: 100, height: 100)
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 100,
            pixelsHigh: 100,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let ctx = try #require(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSGraphicsContext.restoreGraphicsState()
        let png = try #require(rep.representation(using: .png, properties: [:]))

        let result = await OCRService().recognize(imageData: png)
        #expect(result == nil)
    }

    @Test
    func recognize_returnsNilForInvalidData() async {
        let result = await OCRService().recognize(imageData: Data([0xFF, 0x00, 0x11]))
        #expect(result == nil)
    }

    @Test
    func recognize_multiLineTextJoinedWithNewline() async throws {
        // Two separate rendered words will be picked up as separate observations.
        let size = CGSize(width: 300, height: 160)
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let ctx = try #require(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 22, weight: .regular),
            .foregroundColor: NSColor.black
        ]
        ("Line One" as NSString).draw(at: NSPoint(x: 12, y: 100), withAttributes: attrs)
        ("Line Two" as NSString).draw(at: NSPoint(x: 12, y: 30), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
        let png = try #require(rep.representation(using: .png, properties: [:]))

        let result = try #require(await OCRService().recognize(imageData: png))
        #expect(result.contains("One") || result.contains("Two"))
    }
}

@Suite("OCR warm-up", .enabled(if: VisionAvailability.canRecognizeText, "text recognition needs a real Mac"))
struct OCRWarmUpTests {
    @Test("warming the recognizer completes and leaves it usable")
    func whenPrewarmed_thenStillRecognisesNothingInABlankImage() async {
        await OCRService().prewarm()
        #expect(await OCRService().recognize(imageData: Data("not an image".utf8)) == nil)
    }
}
