// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Card text follows the card size")
struct CardTextScaleTests {
    @Test("the medium card, 200 wide, draws text at its normal size")
    func whenMedium_thenUnchanged() {
        #expect(CardTextScale.factor(forWidth: 200) == 1)
        #expect(CardTextScale.size(13, cardWidth: 200) == 13)
    }

    @Test("a large card draws larger text and a small card slightly smaller, in proportion to its width")
    func whenLargeOrSmall_thenInProportion() {
        #expect(CardTextScale.factor(forWidth: 240) == 1.2)
        #expect(CardTextScale.size(13, cardWidth: 240) == 15.6)
        #expect(CardTextScale.factor(forWidth: 180) == 0.9)
    }

    @Test("text never drops below 11 points at the card sizes the slider offers, and growth is capped")
    func whenExtreme_thenClamped() {
        #expect(CardTextScale.factor(forWidth: 160) == 0.85)
        #expect(CardTextScale.size(13, cardWidth: 160) >= 11)
        #expect(CardTextScale.size(12, cardWidth: 150) >= 10.2)
        #expect(CardTextScale.factor(forWidth: 400) == 1.2)
    }

    @Test("a line is as tall as the text, so a larger card still fits as many lines as its height allows")
    func whenCounting_thenLineHeightFollows() {
        #expect(CardTextScale.lineHeight(cardWidth: 200) == 18)
        #expect(abs(CardTextScale.lineHeight(cardWidth: 240) - 21.6) < 0.0001)
    }
}
