// SPDX-License-Identifier: MIT
import CoreGraphics
import Testing
@testable import PestoCore

@Suite("Card layout")
struct CardLayoutTests {
    @Test(
        "without a header band the three card sizes show 6, 7 and 8 lines of text (they showed 4, 5 and 6)",
        arguments: [
            (160, 6), (200, 7), (240, 8)
        ]
    )
    func whenCardSize_thenLineLimit(width: Int, lines: Int) {
        #expect(CardLayout.textLineLimit(for: CardMetrics.dimensions(width: width)) == lines)
    }

    @Test("every width the slider offers shows at least two lines and never fewer than a narrower card")
    func whenSliding_thenLineLimitNeverShrinks() {
        let limits = CardMetrics.sliderRange.map { CardLayout.textLineLimit(for: CardMetrics.dimensions(width: $0)) }
        #expect(limits.allSatisfy { $0 >= 2 })
        #expect(limits == limits.sorted())
    }

    @Test("the lines fit the height budget, so text never meets the footer")
    func whenLinesCounted_thenTheyFitTheBudget() {
        for width in CardMetrics.sliderRange {
            let size = CardMetrics.dimensions(width: width)
            let lines = CGFloat(CardLayout.textLineLimit(for: size))
            #expect(lines * CardTextScale.lineHeight(cardWidth: size.width) <= CardLayout.textHeightBudget(for: size))
        }
    }

    @Test("the content starts at the side margin's distance from the top, and the app icon is 18 points")
    func whenNoHeader_thenContentStartsAtTheTop() {
        #expect(CardLayout.contentTopInset == 10)
        #expect(CardLayout.sourceTileSize == 18)
    }

    @Test("a paragraph gap costs a third of a line at the medium size, and the block holds the line limit exactly")
    func whenBlock_thenLinesTimesLineHeight() {
        let medium = CardMetrics.dimensions(width: 200)
        #expect(CardLayout.textBlockHeight(for: medium) == 126 + CardLayout.lineTolerance)
        #expect(CardLayout.paragraphGap * 3 == CardTextScale.lineHeight(cardWidth: 200))
    }

    @Test("the tolerance never admits another line, at any width the slider offers")
    func whenTolerance_thenNoExtraLine() {
        for width in CardMetrics.sliderRange {
            let size = CardMetrics.dimensions(width: width)
            let line = CardTextScale.lineHeight(cardWidth: size.width)
            let lines = CGFloat(CardLayout.textLineLimit(for: size))
            #expect(CardLayout.textBlockHeight(for: size) < (lines + 1) * line)
            #expect(CardLayout.textBlockHeight(for: size) <= CardLayout.textHeightBudget(for: size) + CardLayout
                .lineTolerance)
        }
    }

    @Test("the glyph tops of both steps sit the same distance under the card's top edge", arguments: [5.9, 4.4, 5.0])
    func whenSizes_thenCapTopFixed(spaceAboveCaps: Double) {
        let padding = CardLayout.largeTextTopPadding(spaceAboveCaps: CGFloat(spaceAboveCaps))
        let capTop = CardLayout.contentTopInset + padding + CGFloat(spaceAboveCaps)
        #expect(abs(capTop - CardLayout.glyphTopInset) < 0.001)
    }

    @Test("the offset never pulls the text up past the top inset and stays inside the allowance")
    func whenTallSpace_thenNoNegativePadding() {
        #expect(CardLayout.largeTextTopPadding(spaceAboveCaps: 40) == 0)
        #expect(CardLayout.largeTextTopPadding(spaceAboveCaps: 3) <= CardLayout.glyphTopInsetAllowance)
    }
}
