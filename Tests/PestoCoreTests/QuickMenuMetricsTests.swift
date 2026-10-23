// SPDX-License-Identifier: MIT
import CoreGraphics
import Testing
@testable import PestoCore

@Suite("QuickMenuMetrics")
struct QuickMenuMetricsTests {
    private let large = CGSize(width: 200, height: 180)

    @Test("the panel is tall enough for a whole card plus its padding, whatever the card size")
    func heightCoversTheCard() {
        for card in [CGSize(width: 160, height: 140), large, CGSize(width: 240, height: 220)] {
            let size = QuickMenuMetrics.panelSize(cardSize: card, cards: 5, maxWidth: 4000)
            #expect(size.height >= card.height + 2 * QuickMenuMetrics.verticalPadding)
        }
    }

    @Test("five default-size cards fit side by side")
    func widthFitsEveryCard() {
        let size = QuickMenuMetrics.panelSize(cardSize: large, cards: 5, maxWidth: 4000)
        #expect(size.width >= 5 * large.width + 4 * QuickMenuMetrics.spacing + 2 * QuickMenuMetrics.horizontalPadding)
    }

    @Test("fewer cards give a narrower panel")
    func fewerCardsNarrower() {
        let two = QuickMenuMetrics.panelSize(cardSize: large, cards: 2, maxWidth: 4000)
        let five = QuickMenuMetrics.panelSize(cardSize: large, cards: 5, maxWidth: 4000)
        #expect(two.width < five.width)
    }

    @Test("an empty history still gets a usable panel")
    func noCardsStillOneSlot() {
        let size = QuickMenuMetrics.panelSize(cardSize: large, cards: 0, maxWidth: 4000)
        #expect(size.width >= large.width)
    }

    @Test("the panel never exceeds the room on the screen; the cards scroll instead")
    func widthIsCappedToTheScreen() {
        let size = QuickMenuMetrics.panelSize(cardSize: large, cards: 5, maxWidth: 600)
        #expect(size.width == 600)
    }
}
