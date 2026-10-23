// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Hex color parsing in Core")
struct HexColorParserTests {
    @Test("parses 6-character hex with or without hash prefix")
    func whenSixCharHex_thenParsesCorrectly() {
        let parsed = HexColorParser.parse("#FF8000")
        #expect(parsed != nil)
        #expect(parsed?.red == 1.0)
        #expect(abs((parsed?.green ?? 0) - (128.0 / 255.0)) < 0.001)
        #expect(parsed?.blue == 0.0)
        #expect(parsed?.alpha == 1.0)

        let noHash = HexColorParser.parse("00FF00")
        #expect(noHash?.red == 0.0)
        #expect(noHash?.green == 1.0)
        #expect(noHash?.blue == 0.0)
        #expect(noHash?.alpha == 1.0)
    }

    @Test("parses 3-character short hex")
    func whenThreeCharHex_thenExpandsToDoubleDigits() {
        let parsed = HexColorParser.parse("#F0A")
        #expect(parsed != nil)
        #expect(parsed?.red == 1.0)
        #expect(parsed?.green == 0.0)
        #expect(abs((parsed?.blue ?? 0) - (0xAA / 255.0)) < 0.001)
        #expect(parsed?.alpha == 1.0)
    }

    @Test("parses 8-character hex with alpha")
    func whenEightCharHex_thenParsesAlpha() {
        let parsed = HexColorParser.parse("0000FF80")
        #expect(parsed != nil)
        #expect(parsed?.red == 0.0)
        #expect(parsed?.green == 0.0)
        #expect(parsed?.blue == 1.0)
        #expect(abs((parsed?.alpha ?? 0) - (128.0 / 255.0)) < 0.001)
    }

    @Test("returns nil for invalid hex strings")
    func whenInvalidString_thenReturnsNil() {
        #expect(HexColorParser.parse("") == nil)
        #expect(HexColorParser.parse("12345") == nil)
        #expect(HexColorParser.parse("ZZZZZZ") == nil)
        #expect(HexColorParser.parse("#12") == nil)
    }

    @Test("computes luminance matching standard formula")
    func whenComputingLuminance_thenMatchesValues() {
        let white = HexColorParser.parse("FFFFFF")
        #expect(abs((white?.luminance ?? 0) - 1.0) < 0.001)

        let black = HexColorParser.parse("000000")
        #expect(abs(black?.luminance ?? 0) < 0.001)
    }

    @Test("parses 4-character hex as #RGBA, each digit doubled")
    func whenFourCharHex_thenExpandsWithAlpha() throws {
        let parsed = try #require(HexColorParser.parse("#F008"))
        #expect(parsed.red == 1.0 && parsed.green == 0.0 && parsed.blue == 0.0)
        #expect(abs(parsed.alpha - (0x88 / 255.0)) < 0.001)
    }
}
