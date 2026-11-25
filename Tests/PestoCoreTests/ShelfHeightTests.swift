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

    @Test("the command block is the top inset, one 28 pt row and the bottom inset, in both modes (Find bar 1b)")
    func commandBlockIsItsRowAndInsets() {
        let parts = ShelfHeight.commandTopInset + ShelfHeight.commandRowHeight + ShelfHeight.commandBottomInset
        #expect(abs(Double(parts) - Double(ShelfHeight.commandBlock)) < 0.001)
        #expect(ShelfHeight.commandBlock == 46)
        #expect(ShelfHeight.commandRowHeight == 28)
    }

    @Test("the search field is as wide as the shelf allows, between 320 and 480 pt")
    func searchFieldWidth() {
        #expect(ShelfHeight.searchFieldWidth(shelfWidth: 1512) == 480)
        #expect(ShelfHeight.searchFieldWidth(shelfWidth: 1280) == 410)
        #expect(ShelfHeight.searchFieldWidth(shelfWidth: 900) == 320)
    }

    @Test("the band under the cards holds the selection bar's 30 pt capsule with room above and below it")
    func bandHoldsTheSelectionBar() {
        let band = ShelfHeight.liftRoom / 2 + ShelfHeight.bottomSlot
        #expect(band >= 30 + 2 * 8)
    }

    @Test("search chrome matches the rest chrome so opening search never jumps the shelf or moves the cards")
    func searchChromeMatchesChromeBudget() {
        #expect(ShelfHeight.topOverflow(measuredHeight: 46, isSearchActive: false) == 0)
        #expect(ShelfHeight.topOverflow(measuredHeight: 46, isSearchActive: true) == 0)
        #expect(ShelfHeight.topOverflow(measuredHeight: 78, isSearchActive: false) == 32)
        #expect(ShelfHeight.topOverflow(measuredHeight: 78, isSearchActive: true) == 32)
        #expect(ShelfHeight.bottomCapsuleInset(isSearchActive: false) == 8)
        #expect(ShelfHeight.bottomCapsuleInset(isSearchActive: true) == 8)
    }
}
