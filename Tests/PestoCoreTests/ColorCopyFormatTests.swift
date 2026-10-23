// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Colour literals and Copy As")
struct ColorCopyFormatTests {
    private func parsed(_ text: String) -> HexColorComponents? {
        ColorLiteralParser.firstColor(in: text)
    }

    @Test("a hex, rgb or hsl literal inside text is read, and plain text has none")
    func whenTextHoldsALiteral_thenItIsRead() throws {
        let hex = try #require(parsed("background: #2F7A49;"))
        #expect(ColorCopyFormat.rgb.string(for: hex) == "rgb(47, 122, 73)")
        #expect(parsed("rgb(47, 122, 73)") == hex)
        let hsl = try #require(parsed("hsl(140, 45%, 33%)"))
        #expect(hsl.red < hsl.green)
        #expect(parsed("Thank you for your order") == nil)
        #expect(parsed("rgb(300, 0, 0)") == nil)
    }

    @Test("a short hex is expanded and an eight-digit hex carries its alpha")
    func whenShortOrAlpha_thenExpanded() throws {
        let short = try #require(parsed("#0af"))
        #expect(ColorCopyFormat.hex.string(for: short) == "#00AAFF")
        let alpha = try #require(parsed("#2F7A4980"))
        #expect(ColorCopyFormat.hex.string(for: alpha) == "#2F7A4980")
        #expect(ColorCopyFormat.rgb.string(for: alpha) == "rgba(47, 122, 73, 0.5)")
    }

    @Test("every format of one colour")
    func whenFormatted_thenEachFormatReads() throws {
        let color = try #require(parsed("#2F7A49"))
        #expect(ColorCopyFormat.hex.string(for: color) == "#2F7A49")
        #expect(ColorCopyFormat.hexNoHash.string(for: color) == "2F7A49")
        #expect(ColorCopyFormat.rgb.string(for: color) == "rgb(47, 122, 73)")
        #expect(ColorCopyFormat.hsl.string(for: color) == "hsl(141, 44%, 33%)")
        #expect(ColorCopyFormat.cmyk.string(for: color) == "cmyk(61%, 0%, 40%, 52%)")
        #expect(ColorCopyFormat.oklch.string(for: color).hasPrefix("oklch("))
        #expect(ColorCopyFormat.swiftUI.string(for: color) == "Color(red: 0.184, green: 0.478, blue: 0.286)")
        #expect(
            ColorCopyFormat.nsColor.string(for: color)
                == "NSColor(srgbRed: 0.184, green: 0.478, blue: 0.286, alpha: 1)"
        )
    }

    @Test("black, white and a grey have no hue to print")
    func whenGrey_thenHueIsZero() throws {
        #expect(try ColorCopyFormat.hsl.string(for: #require(parsed("#000000"))) == "hsl(0, 0%, 0%)")
        #expect(try ColorCopyFormat.hsl.string(for: #require(parsed("#FFFFFF"))) == "hsl(0, 0%, 100%)")
        #expect(try ColorCopyFormat.hsl.string(for: #require(parsed("#808080"))) == "hsl(0, 0%, 50%)")
        #expect(try ColorCopyFormat.cmyk.string(for: #require(parsed("#000000"))) == "cmyk(0%, 0%, 0%, 100%)")
        #expect(try ColorCopyFormat.cmyk.string(for: #require(parsed("#FFFFFF"))) == "cmyk(0%, 0%, 0%, 0%)")
    }

    @Test("an alpha colour keeps its opacity in the code formats")
    func whenAlpha_thenCodeFormatsKeepIt() throws {
        let color = try #require(parsed("#2F7A4980"))
        #expect(ColorCopyFormat.hexNoHash.string(for: color) == "2F7A4980")
        #expect(ColorCopyFormat.swiftUI.string(for: color).hasSuffix(", opacity: 0.5)"))
        #expect(ColorCopyFormat.nsColor.string(for: color).hasSuffix("alpha: 0.5)"))
        #expect(ColorCopyFormat.hsl.string(for: color).hasPrefix("hsla("))
        #expect(ColorCopyFormat.oklch.string(for: color).hasSuffix("/ 0.5)"))
    }

    @Test("the formats the menu offers are in a fixed order")
    func whenListed_thenFixedOrder() {
        #expect(ColorCopyFormat.allCases == [.hex, .hexNoHash, .rgb, .hsl, .cmyk, .oklch, .swiftUI, .nsColor])
    }
}
