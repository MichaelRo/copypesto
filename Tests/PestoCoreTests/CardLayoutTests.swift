// SPDX-License-Identifier: MIT
import CoreGraphics
import Testing
@testable import PestoCore

@Suite("Card layout")
struct CardLayoutTests {
    @Test("the three card sizes show 4, 5 and 6 lines of text", arguments: [
        (160, 4), (200, 5), (240, 6)
    ])
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

    @Test("the header band is 34 points, with a 20 point app tile")
    func whenHeader_thenQuietBand() {
        #expect(CardLayout.headerHeight == 34)
        #expect(CardLayout.appTileSize == 20)
    }

    @Test("a paragraph gap costs a third of a line at the medium size, and the block holds the line limit exactly")
    func whenBlock_thenLinesTimesLineHeight() {
        let medium = CardMetrics.dimensions(width: 200)
        #expect(CardLayout.textBlockHeight(for: medium) == 90 + CardLayout.lineTolerance)
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
}
