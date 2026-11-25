// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("ColorLiteralParser")
struct ColorLiteralParserTests {
    @Test("an issue or pull request number is not a colour", arguments: [
        "Fixed in #178", "see #404 and #500", "PRs #177, #178 and #179", "Closes #123."
    ])
    func whenReferenceNumber_thenNoColor(text: String) {
        #expect(ColorLiteralParser.firstColor(in: text) == nil)
    }

    @Test("an HTML character reference, or a hash glued to a word, is not a colour", arguments: [
        "&#178; and &#123;", "PR#178", "id#abc"
    ])
    func whenNotAStandaloneHash_thenNoColor(text: String) {
        #expect(ColorLiteralParser.firstColor(in: text) == nil)
    }

    @Test("a colour is still found, after a reference number if there is one", arguments: [
        "color: #2f7a49;", "#fff", "Issue #178, brand green #2f7a49", "grey #000 and #999"
    ])
    func whenRealColor_thenFound(text: String) {
        #expect(ColorLiteralParser.firstColor(in: text) != nil)
    }

    @Test("the colour after a reference number is the one that is returned")
    func whenReferenceThenColor_thenTheColor() throws {
        let found = try #require(ColorLiteralParser.firstColor(in: "Issue #178, brand green #FF0000"))

        #expect(found.red == 1)
        #expect(found.green == 0)
    }

    @Test("#RGBA inside a text is a colour with a digit or four equal characters, with its alpha")
    func whenHashRGBA_thenColorWithAlpha() throws {
        let found = try #require(ColorLiteralParser.firstColor(in: "overlay: #f008;"))
        #expect(found.red == 1 && found.green == 0 && found.blue == 0)
        #expect(abs(found.alpha - 0.5333) < 0.01)
        #expect(ColorLiteralParser.firstColor(in: "white #ffff") != nil)
    }

    @Test("a four-character hash that is a hashtag or a reference number is not a colour", arguments: [
        "#cafe", "love #face today", "Fixed in #1234", "tag #abcd"
    ])
    func whenHashFourAmbiguous_thenNoColor(text: String) {
        #expect(ColorLiteralParser.firstColor(in: text) == nil)
    }

    @Test("rgb() and hsl() in the space syntax, with a slash alpha and percent channels", arguments: [
        ("rgb(255 0 0)", 1.0, 0.0, 0.0, 1.0),
        ("rgb(255 0 0 / 50%)", 1.0, 0.0, 0.0, 0.5),
        ("rgba(255 0 0 / .5)", 1.0, 0.0, 0.0, 0.5),
        ("color: rgb(100% 0% 0% / 0.25);", 1.0, 0.0, 0.0, 0.25),
        ("rgb(255, 0, 0, 0.5)", 1.0, 0.0, 0.0, 0.5),
        ("hsl(120deg 100% 50%)", 0.0, 1.0, 0.0, 1.0),
        ("hsl(120 100% 50% / 0.5)", 0.0, 1.0, 0.0, 0.5),
        ("hsla(240, 100%, 50%, 25%)", 0.0, 0.0, 1.0, 0.25)
    ])
    func whenSpaceSyntax_thenParsed(text: String, red: Double, green: Double, blue: Double, alpha: Double) throws {
        let found = try #require(ColorLiteralParser.firstColor(in: text))
        #expect(abs(found.red - red) < 0.01, "\(text)")
        #expect(abs(found.green - green) < 0.01, "\(text)")
        #expect(abs(found.blue - blue) < 0.01, "\(text)")
        #expect(abs(found.alpha - alpha) < 0.01, "\(text)")
    }

    @Test("a channel above 255 or a missing channel is not a colour", arguments: [
        "rgb(300 0 0)", "rgb(255 0)", "rgb(1 2 3 4 5)", "hsl(120 150% 50%)"
    ])
    func whenOutOfRange_thenNoColor(text: String) {
        #expect(ColorLiteralParser.firstColor(in: text) == nil, "\(text)")
    }

    @Test(
        "color(fromWholeString:) parses bare 6/8-char hex while rejecting bare words, numbers, and prose",
        arguments: [
            ("FF8800", true),
            ("a1b2c3", true),
            ("FF880080", true),
            ("decade", false),
            ("123456", false),
            ("order FF8800", false)
        ]
    )
    func whenBareHexWholeString_thenMatchesClassifierPolicy(text: String, expected: Bool) {
        let parsed = ColorLiteralParser.color(fromWholeString: text)
        #expect((parsed != nil) == expected, "\(text)")
        if expected {
            #expect(ColorLiteralParser.firstColor(in: "order \(text)") == nil)
        }
    }

    @Test("hsl supports rad, grad, turn, and negative hues")
    func whenHslAngleUnits_thenParsed() throws {
        let turn = try #require(ColorLiteralParser.color(fromWholeString: "hsl(0.5turn 100% 50%)"))
        #expect(abs(turn.red) < 0.01 && abs(turn.green - 1.0) < 0.01 && abs(turn.blue - 1.0) < 0.01)

        let negative = try #require(ColorLiteralParser.color(fromWholeString: "hsl(-120deg 100% 50%)"))
        #expect(abs(negative.red) < 0.01 && abs(negative.green) < 0.01 && abs(negative.blue - 1.0) < 0.01)

        let rad = try #require(ColorLiteralParser.color(fromWholeString: "hsl(2.0944rad 100% 50%)"))
        #expect(abs(rad.green - 1.0) < 0.02)

        let grad = try #require(ColorLiteralParser.color(fromWholeString: "hsl(200grad 100% 50%)"))
        #expect(abs(grad.green - 1.0) < 0.01 && abs(grad.blue - 1.0) < 0.01)
    }

    @Test("oklch, oklab, hwb, color(...), and cmyk(...) convert accurately to sRGB")
    func whenModernSchemas_thenParsed() throws {
        let oklch = try #require(ColorLiteralParser.color(fromWholeString: "oklch(0.628 0.258 29.2)"))
        #expect(oklch.red > 0.9 && oklch.green < 0.15 && oklch.blue < 0.1)

        let oklchAlpha = try #require(ColorLiteralParser.color(fromWholeString: "oklch(62.8% 64.5% 29.2deg / 50%)"))
        #expect(abs(oklchAlpha.alpha - 0.5) < 0.01 && oklchAlpha.red > 0.9)

        let oklab = try #require(ColorLiteralParser.color(fromWholeString: "oklab(0.628 0.225 0.126)"))
        #expect(oklab.red > 0.9 && oklab.green < 0.15)

        let hwb = try #require(ColorLiteralParser.color(fromWholeString: "hwb(120 0% 0% / 0.5)"))
        #expect(abs(hwb.red) < 0.01 && abs(hwb.green - 1.0) < 0.01 && abs(hwb.blue) < 0.01 && abs(hwb.alpha - 0.5) <
            0.01)

        let srgb = try #require(ColorLiteralParser.color(fromWholeString: "color(srgb 0.5 0.25 1 / 0.75)"))
        #expect(abs(srgb.red - 0.5) < 0.001 && abs(srgb.green - 0.25) < 0.001 && abs(srgb.blue - 1.0) < 0.001)
        #expect(abs(srgb.alpha - 0.75) < 0.001)

        let linear = try #require(ColorLiteralParser.color(fromWholeString: "color(srgb-linear 1 0 0)"))
        #expect(abs(linear.red - 1.0) < 0.001 && abs(linear.green) < 0.001)

        let p3 = try #require(ColorLiteralParser.color(fromWholeString: "color(display-p3 1 0 0)"))
        #expect(p3.red > 0.99 && p3.green < 0.01 && p3.blue < 0.01)

        let cmyk = try #require(ColorLiteralParser.color(fromWholeString: "cmyk(61%, 0%, 40%, 52%)"))
        #expect(abs(cmyk.red - 0.1872) < 0.01 && abs(cmyk.green - 0.48) < 0.01 && abs(cmyk.blue - 0.288) < 0.01)
    }

    @Test("Copy As OKLCH and CMYK formats round-trip through ColorLiteralParser")
    func whenCopyAsFormatted_thenRoundTrips() throws {
        let base = try #require(HexColorParser.parse("#2F7A49"))
        let oklchText = ColorCopyFormat.oklch.string(for: base)
        let parsedOklch = try #require(ColorLiteralParser.color(fromWholeString: oklchText))
        #expect(abs(parsedOklch.red - base.red) < 0.01)
        #expect(abs(parsedOklch.green - base.green) < 0.01)
        #expect(abs(parsedOklch.blue - base.blue) < 0.01)

        let cmykText = ColorCopyFormat.cmyk.string(for: base)
        let parsedCmyk = try #require(ColorLiteralParser.color(fromWholeString: cmykText))
        #expect(abs(parsedCmyk.red - base.red) < 0.01)
        #expect(abs(parsedCmyk.green - base.green) < 0.01)
        #expect(abs(parsedCmyk.blue - base.blue) < 0.01)
    }

    @Test("overflowing angle units never produce NaN components or crash")
    func whenOverflowingAngle_thenReturnsNilWithoutNaN() {
        let huge = String(repeating: "9", count: 308)
        for input in [
            "hsl(1e308turn 50% 50%)",
            "oklch(0.6 0.1 1e308turn)",
            "hwb(1e308turn 10% 10%)",
            "hsl(1e308rad 50% 50%)",
            "hsl(\(huge)turn 50% 50%)",
            "oklch(0.6 0.1 \(huge)turn)",
            "hwb(\(huge)turn 10% 10%)"
        ] {
            #expect(ColorLiteralParser.color(fromWholeString: input) == nil, "\(input)")
            #expect(ColorLiteralParser.firstColor(in: input) == nil, "\(input)")
        }
    }

    @Test("long malformed functional color text fails fast without regex backtracking")
    func whenLongMalformedFunctionalInput_thenRejectsQuickly() {
        let a = String(repeating: "1", count: 40)
        let b = String(repeating: "2", count: 40)
        let c = String(repeating: "3", count: 40)
        let d = String(repeating: "4", count: 40)
        let input = "rgb(\(a) \(b) \(c) / \(d)x)"
        #expect(ColorLiteralParser.firstColor(in: input) == nil)
        #expect(ColorLiteralParser.color(fromWholeString: input) == nil)
    }
}
