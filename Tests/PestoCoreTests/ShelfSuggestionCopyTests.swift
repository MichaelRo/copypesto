// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Shelf suggestion copy and localizations")
struct ShelfSuggestionCopyTests {
    @Test("when one paste, says 1 time, and multiple pastes says times")
    func whenCounts_thenFormattedCorrectly() {
        let single = ShelfSuggestionCopy.shortcutOfferTitle(pasteCount: 1, keyString: "⌃1", isPinned: false)
        #expect(single.contains("1 time"))

        let plural = ShelfSuggestionCopy.shortcutOfferTitle(pasteCount: 6, keyString: "⌃3", isPinned: false)
        #expect(plural.contains("6 times"))
    }

    @Test("when dormant weeks, formats weeks count")
    func whenWeeks_thenFormatted() {
        let text = ShelfSuggestionCopy.dormantTitle(keyString: "⌃4", weeks: 8)
        #expect(text.contains("8 weeks"))
        #expect(text.contains("⌃4"))
    }

    @Test("copy never contains magic, slot, or banned terms")
    func whenAnyText_thenNoSlotOrMagicWord() {
        let offerUnpinned = ShelfSuggestionCopy.shortcutOfferTitle(pasteCount: 6, keyString: "⌃3", isPinned: false)
        let offerPinned = ShelfSuggestionCopy.shortcutOfferTitle(pasteCount: 6, keyString: "⌃3", isPinned: true)
        let dormant = ShelfSuggestionCopy.dormantTitle(keyString: "⌃4", weeks: 8)
        let reminder = ShelfSuggestionCopy.reminderTitle(shelfPastes: 5, keyString: "⌃3")
        let snippet = ShelfSuggestionCopy.snippetTitle()
        let off = ShelfSuggestionCopy.offNoticeTitle

        let allTexts = [offerUnpinned, offerPinned, dormant, reminder, snippet, off]
        for sentence in allTexts {
            #expect(!sentence.localizedCaseInsensitiveContains("magic"))
            #expect(!sentence.localizedCaseInsensitiveContains("slot"))
            #expect(!sentence.localizedCaseInsensitiveContains("seamless"))
            #expect(!sentence.localizedCaseInsensitiveContains("effortless"))
        }
    }

    @Test("when offer is for unpinned clip it says Pin it, and for pinned clip it does not say Pin it")
    func whenOfferPinnedState_thenReflectsInText() {
        let unpinned = ShelfSuggestionCopy.shortcutOfferTitle(pasteCount: 6, keyString: "⌃3", isPinned: false)
        #expect(unpinned.contains("Pin it"))

        let pinned = ShelfSuggestionCopy.shortcutOfferTitle(pasteCount: 6, keyString: "⌃3", isPinned: true)
        #expect(!pinned.contains("Pin it"))
    }
}
