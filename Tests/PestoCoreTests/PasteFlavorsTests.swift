// SPDX-License-Identifier: MIT
import AppKit
import Testing
@testable import PestoCore

@Suite("PasteFlavors")
@MainActor
struct PasteFlavorsTests {
    @Test("a stored URL also yields its text, for fields that ignore public.url")
    func whenStoredURL_thenTextFlavourIsTheURLString() {
        let data = Data("https://example.com/a?b=1".utf8)

        #expect(PasteFlavors.plainText(forStoredType: "public.url", data: data) == "https://example.com/a?b=1")
    }

    @Test("stored RTF from before rich text was flattened yields its plain text, not markup")
    func whenStoredRTF_thenTextFlavourIsFlattened() throws {
        let attributed = NSAttributedString(string: "legacy note")
        let rtf = try #require(attributed.rtf(from: NSRange(location: 0, length: attributed.length)))

        #expect(PasteFlavors.plainText(forStoredType: "public.rtf", data: rtf) == "legacy note")
    }

    @Test("plain text, images and files need no extra flavour")
    func whenAlreadyTextOrNotTextual_thenNoExtraFlavour() {
        let data = Data("x".utf8)

        #expect(PasteFlavors.plainText(forStoredType: "public.utf8-plain-text", data: data) == nil)
        #expect(PasteFlavors.plainText(forStoredType: "public.png", data: data) == nil)
        #expect(PasteFlavors.plainText(forStoredType: "public.file-url", data: data) == nil)
    }

    @Test("a stored PNG image yields a TIFF companion flavour for Cocoa editors")
    func whenStoredPNG_thenCompanionIsTIFF() throws {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 60, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let png = try #require(rep.representation(using: .png, properties: [:]))
        let companions = PasteFlavors.companionImageFlavors(forStoredType: "public.png", data: png)

        #expect(companions.count == 1)
        #expect(companions.first?.type == .tiff)
        if let tiffData = companions.first?.data, let tiffRep = NSBitmapImageRep(data: tiffData) {
            #expect(tiffRep.pixelsWide == 100)
            #expect(tiffRep.pixelsHigh == 60)
        }
    }

    @Test("a stored TIFF image yields a PNG companion flavour for Web and Electron editors")
    func whenStoredTIFF_thenCompanionIsPNG() throws {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 40, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let tiff = try #require(rep.tiffRepresentation)
        let companions = PasteFlavors.companionImageFlavors(forStoredType: "public.tiff", data: tiff)

        #expect(companions.count == 1)
        #expect(companions.first?.type == .png)
        if let pngData = companions.first?.data, let pngRep = NSBitmapImageRep(data: pngData) {
            #expect(pngRep.pixelsWide == 80)
            #expect(pngRep.pixelsHigh == 40)
        }
    }

    @Test("a stored WebP image yields a PNG companion flavour")
    func whenStoredWebP_thenCompanionIsPNG() throws {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 50, pixelsHigh: 50, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let png = try #require(rep.representation(using: .png, properties: [:]))
        let companions = PasteFlavors.companionImageFlavors(forStoredType: "org.webmproject.webp", data: png)

        #expect(companions.count == 1)
        #expect(companions.first?.type == .png)
    }

    @Test("an animated GIF yields PNG companion but never TIFF so receiving Cocoa apps preserve animation")
    func whenGIF_thenYieldsPNGAndNoTIFF() throws {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let gif = try #require(rep.representation(using: .gif, properties: [:]))
        let companions = PasteFlavors.companionImageFlavors(forStoredType: "com.compuserve.gif", data: gif)

        #expect(companions.count == 1)
        #expect(companions.first?.type == .png)
        #expect(!companions.contains(where: { $0.type == .tiff }))
    }

    @Test("non-image types yield no companion image flavours")
    func whenNonImage_thenNoCompanionFlavours() {
        let textData = Data("hello".utf8)
        #expect(PasteFlavors.companionImageFlavors(forStoredType: "public.utf8-plain-text", data: textData).isEmpty)
        #expect(PasteFlavors.companionImageFlavors(forStoredType: "public.url", data: textData).isEmpty)
    }
}
