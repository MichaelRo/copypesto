// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("What a covered card's menu offers")
struct CardMenuItemTests {
    @Test("a card that is not covered offers every item, as before")
    func normalCardUnchanged() {
        for item in CardMenuItem.allCases {
            #expect(item.isOffered(covered: false), "\(item) is missing from a normal card's menu")
        }
    }

    @Test("a covered card offers only paste, paste as plain text, copy and delete")
    func coveredCardOffersFour() {
        let offered = Set(CardMenuItem.allCases.filter { $0.isOffered(covered: true) })
        #expect(offered == [.paste, .pastePlain, .copy, .delete])
    }

    @Test("entity, link, color, rename, note, expiry, shortcut, pin, tag and collection items are absent when covered")
    func coveredCardNamesNothing() {
        let named: [CardMenuItem] = [
            .entityActions, .openLink, .showInFinder, .colorCopyFormats, .rename, .note, .setExpiry,
            .assignShortcut, .pin, .tag, .icon, .clearCustomizations, .moveToCollection, .aiActions,
            .copyLinkPreview, .copyTransformed, .pasteTransformed, .markSensitive, .quickLook
        ]
        for item in named {
            #expect(!item.isOffered(covered: true), "\(item) is offered on a covered card")
        }
    }
}
