// SPDX-License-Identifier: MIT
import AppKit
import Testing
@testable import PestoCore

@Suite("PasteboardTypeDetector")
struct PasteboardTypeDetectorTests {
    @Test("prefers fileURL over URL when both are present (Finder copy)")
    func whenFileURLAndURL_thenFileURL() {
        let detected = PasteboardTypeDetector.detect(types: [.URL, .fileURL, .string])
        #expect(detected == .fileURL)
    }

    @Test("prefers PNG over TIFF when both are present")
    func whenPNGAndTIFF_thenPNG() {
        let detected = PasteboardTypeDetector.detect(types: [.tiff, .png])
        #expect(detected == .png)
    }

    @Test("a GIF beats the still PNG or TIFF a browser adds beside it, so the copy keeps moving")
    func whenGIFAndStillPictures_thenGIF() {
        let gif = NSPasteboard.PasteboardType("com.compuserve.gif")
        #expect(PasteboardTypeDetector.detect(types: [.tiff, .png, gif]) == gif)
        #expect(PasteboardTypeDetector.detect(types: [.png, NSPasteboard.PasteboardType("public.gif")])
            == NSPasteboard.PasteboardType("public.gif"))
    }

    @Test("prefers URL over string for browser-style copies")
    func whenURLAndString_thenURL() {
        let detected = PasteboardTypeDetector.detect(types: [.string, .URL])
        #expect(detected == .URL)
    }

    @Test("prefers RTF over plain string")
    func whenRTFAndString_thenRTF() {
        let detected = PasteboardTypeDetector.detect(types: [.string, .rtf])
        #expect(detected == .rtf)
    }

    @Test("a board with only a PDF or an SVG is captured as an image-like clip")
    func whenOnlyPDFOrSVG_thenImage() {
        let pdf = NSPasteboard.PasteboardType("com.adobe.pdf")
        let svg = NSPasteboard.PasteboardType("public.svg-image")
        #expect(PasteboardTypeDetector.detect(types: [pdf]) == pdf)
        #expect(PasteboardTypeDetector.detect(types: [svg]) == svg)
        #expect(PasteboardTypeDetector.clipboardType(for: pdf) == .image)
        #expect(PasteboardTypeDetector.clipboardType(for: svg) == .image)
    }

    @Test("PDF and SVG are a last resort: text, a bitmap or a file on the same board wins")
    func whenPDFAlongsideOthers_thenOthersWin() {
        let pdf = NSPasteboard.PasteboardType("com.adobe.pdf")
        #expect(PasteboardTypeDetector.detect(types: [pdf, .string]) == .string)
        #expect(PasteboardTypeDetector.detect(types: [pdf, .png]) == .png)
        #expect(PasteboardTypeDetector.detect(types: [pdf, .fileURL]) == .fileURL)
        #expect(PasteboardTypeDetector.detect(types: [NSPasteboard.PasteboardType("public.svg-image"), pdf]) == pdf)
    }

    @Test("returns nil for unrecognized types")
    func whenUnknown_thenNil() {
        let detected = PasteboardTypeDetector.detect(types: [.init("com.example.unknown")])
        #expect(detected == nil)
    }

    @Test("maps fileURL to .file")
    func fileURLMapsToFile() {
        #expect(PasteboardTypeDetector.clipboardType(for: .fileURL) == .file)
    }

    @Test("maps PNG and TIFF to .image")
    func imageMappings() {
        #expect(PasteboardTypeDetector.clipboardType(for: .png) == .image)
        #expect(PasteboardTypeDetector.clipboardType(for: .tiff) == .image)
    }

    @Test("maps URL to .url")
    func URLMapping() {
        #expect(PasteboardTypeDetector.clipboardType(for: .URL) == .url)
    }

    @Test("maps text variants to .text")
    func textMappings() {
        #expect(PasteboardTypeDetector.clipboardType(for: .string) == .text)
        #expect(PasteboardTypeDetector.clipboardType(for: .rtf) == .text)
        #expect(PasteboardTypeDetector.clipboardType(for: .rtfd) == .text)
    }
}
