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
}
