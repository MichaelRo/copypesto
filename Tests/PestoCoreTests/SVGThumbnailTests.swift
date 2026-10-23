// SPDX-License-Identifier: MIT
import Foundation
import ImageIO
import Testing
@testable import PestoCore

@Suite("SVG thumbnails")
@MainActor
struct SVGThumbnailTests {
    private let svg = Data(
        """
        <svg xmlns='http://www.w3.org/2000/svg' width='120' height='60' viewBox='0 0 120 60'>\
        <rect width='120' height='60' fill='#2F7A49'/></svg>
        """.utf8
    )

    private func size(of png: Data) throws -> (Int, Int) {
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image.width, image.height)
    }

    @Test("an SVG is rendered to a PNG that fits the requested size and keeps its proportions")
    func whenSVG_thenScaledPNG() throws {
        let png = try #require(SVGThumbnail.png(from: svg, maxPixel: 240))

        let (width, height) = try size(of: png)

        #expect(width == 240)
        #expect(height == 120)
    }

    @Test("bytes that are not an SVG give nothing")
    func whenNotSVG_thenNil() {
        #expect(SVGThumbnail.png(from: Data("not an svg".utf8), maxPixel: 100) == nil)
    }

    @Test("SVG data is recognised by its content, not only by the type the app reported")
    func whenChecked_thenLooksLikeSVG() {
        #expect(SVGThumbnail.looksLikeSVG(svg))
        #expect(!SVGThumbnail.looksLikeSVG(Data("%PDF-1.4".utf8)))
        #expect(SVGThumbnail.looksLikeSVG(Data("<?xml version=\"1.0\"?><svg xmlns=\"x\"/>".utf8)))
    }

    @Test("a document over the size cap is refused instead of parsed on the main actor")
    func whenTooLarge_thenNil() {
        let padding = String(repeating: " ", count: SVGThumbnail.maxBytes)
        let huge = Data("<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'>\(padding)</svg>".utf8)

        #expect(SVGThumbnail.png(from: huge, maxPixel: 100) == nil)
    }

    @Test("the output never exceeds the pixel cap, whatever size is asked for")
    func whenHugeSizeAsked_thenClamped() throws {
        let png = try #require(SVGThumbnail.png(from: svg, maxPixel: 100_000))

        let (width, _) = try size(of: png)

        #expect(width == SVGThumbnail.maxPixel)
    }
}
