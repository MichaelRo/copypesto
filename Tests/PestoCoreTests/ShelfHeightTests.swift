// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("ShelfHeight")
struct ShelfHeightTests {
    @Test("the shelf is tall enough for the cards plus the command bar, padding and card lift")
    func heightCoversCardsAndChrome() {
        #expect(ShelfHeight.height(forCardHeight: 180) >= 180 + ShelfHeight.chrome)
    }

    @Test("larger cards give a taller shelf")
    func biggerCardsTallerShelf() {
        #expect(ShelfHeight.height(forCardHeight: 180) > ShelfHeight.height(forCardHeight: 140))
    }

    @Test("Large cards no longer clip: the shelf exceeds the old fixed 280 pt")
    func largeCardsExceedOldFixedHeight() {
        #expect(ShelfHeight.height(forCardHeight: 180) > 280)
    }

    @Test("the chrome is the command bar, the lift room and the bottom slot, and nothing else")
    func chromeIsItsThreeParts() {
        let parts = Double(ShelfHeight.commandBlock) + Double(ShelfHeight.liftRoom) + Double(ShelfHeight.bottomSlot)
        let chrome = Double(ShelfHeight.chrome)
        #expect(chrome == parts)
        #expect(chrome == 112)
    }

    @Test("the band under the cards holds the selection bar's 30 pt capsule with room above and below it")
    func bandHoldsTheSelectionBar() {
        let band = ShelfHeight.liftRoom / 2 + ShelfHeight.bottomSlot
        #expect(band >= 30 + 2 * 8)
    }
}
