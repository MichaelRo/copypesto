// SPDX-License-Identifier: MIT
import SwiftUI
import Testing
@testable import Pesto

@Suite("Colour detection in a card's text")
struct ColorStringDetectorTests {
    @Test("a hex, rgb or hsl literal is found, and plain text has none")
    func finds_literalsAndNothingElse() {
        #expect(ColorStringDetector.detect(in: "background: #2F7A49;") != nil)
        #expect(ColorStringDetector.detect(in: "rgb(47, 122, 73)") != nil)
        #expect(ColorStringDetector.detect(in: "hsl(140, 45%, 33%)") != nil)
        #expect(ColorStringDetector.detect(in: "Thank you for your order") == nil)
    }

    @Test("asking again for the same text gives the same answer, found or not")
    func repeatedAsks_agree() {
        let withColour = "accent #6DBE85"
        let without = "no colour here, only words"
        for _ in 0..<3 {
            #expect(ColorStringDetector.detect(in: withColour) != nil)
            #expect(ColorStringDetector.detect(in: without) == nil)
        }
    }

    @Test("whole-string detection covers bare hex, oklch, oklab, hwb, color(...), and cmyk without breaking prose")
    func wholeColorDetection_coversModernSchemasAndBareHex() {
        #expect(ColorStringDetector.detectWholeColor(in: "FF8800") != nil)
        #expect(ColorStringDetector.detectWholeColor(in: "oklch(0.628 0.258 29.2)") != nil)
        #expect(ColorStringDetector.detectWholeColor(in: "oklab(0.6 -0.1 0.1)") != nil)
        #expect(ColorStringDetector.detectWholeColor(in: "hwb(120 0% 0%)") != nil)
        #expect(ColorStringDetector.detectWholeColor(in: "color(display-p3 0.2 0.5 0.3)") != nil)
        #expect(ColorStringDetector.detectWholeColor(in: "cmyk(61%, 0%, 40%, 52%)") != nil)
        #expect(ColorStringDetector.detectWholeColor(in: "decade") == nil)
        #expect(ColorStringDetector.detectWholeColor(in: "order FF8800") == nil)
    }
}
