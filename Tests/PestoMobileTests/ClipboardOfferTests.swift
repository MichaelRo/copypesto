// SPDX-License-Identifier: MIT
import Foundation
import Testing
import UIKit
@testable import PestoCore
@testable import PestoMobile

extension MobilePasteboardGlobals {
    @Suite("What was copied elsewhere is offered once, and read only when the person asked for it", .serialized)
    @MainActor
    struct ClipboardOfferTests {
        @Test("a new change with something in it is offered, or added when adding is on; anything else is nothing")
        func whenDeciding_thenOnlyANewChangeCounts() {
            #expect(ClipboardOffer
                .decide(changeCount: 5, lastSeen: 4, hasContent: true, addsAutomatically: false) == .offer)
            #expect(ClipboardOffer
                .decide(changeCount: 5, lastSeen: 4, hasContent: true, addsAutomatically: true) == .addNow)
            #expect(ClipboardOffer
                .decide(changeCount: 5, lastSeen: 5, hasContent: true, addsAutomatically: true) == .nothing)
            #expect(ClipboardOffer.decide(changeCount: 6, lastSeen: 5, hasContent: false, addsAutomatically: false)
                == .nothing)
        }

        private func pasteboard() -> UIPasteboard {
            UIPasteboard.withUniqueName()
        }

        @Test("with adding off the change is offered once, and Pesto's own copy is never offered")
        func whenAddingIsOff_thenOfferedOnceAndNeverPestosOwn() async throws {
            let library = try await MobileTestLibrary()
            let board = pasteboard()
            // A throwaway store: the last-seen change count is one process-wide setting that every other suite's
            // activation writes, so on a busy runner it changed under this test.
            let defaults = ThrowawayDefaults.make()
            defaults.set(false, for: Setting.addsCopiesOnOpen)
            board.string = "copied in Safari"

            await library.state.clipboardDidBecomeActive(pasteboard: board, defaults: defaults)
            #expect(library.state.clipboardOfferCount == board.changeCount)
            try await library.refreshed()
            #expect(!library.store.items.contains { $0.displayPreviewText == "copied in Safari" }, "nothing was read")

            library.state.dismissClipboardOffer()
            await library.state.clipboardDidBecomeActive(pasteboard: board, defaults: defaults)
            #expect(library.state.clipboardOfferCount == nil, "the same change is not offered twice")

            MobileClipboard.write(.text("copied from Pesto"), protected: false, to: board, defaults: defaults)
            await library.state.clipboardDidBecomeActive(pasteboard: board, defaults: defaults)
            #expect(library.state.clipboardOfferCount == nil, "Pesto's own copy is not offered")
        }

        @Test("with adding on, the change is read and added through the capture path, marked as pasted")
        func whenAddingIsOn_thenItIsAdded() async throws {
            let library = try await MobileTestLibrary()
            let board = pasteboard()
            let defaults = ThrowawayDefaults.make()
            defaults.set(true, for: Setting.addsCopiesOnOpen)
            board.string = "added on open"

            await library.state.clipboardDidBecomeActive(pasteboard: board, defaults: defaults)
            try await library.refreshed()

            #expect(library.state.clipboardOfferCount == nil)
            #expect(library.store.items
                .contains { $0.displayPreviewText == "added on open" && $0.captureMethod == .paste })
        }

        @Test("auto-add and taking the clipboard offer use the default paste collection when configured")
        func whenDefaultPasteCollectionConfigured_thenAutoAddAndOfferUseIt() async throws {
            let library = try await MobileTestLibrary()
            let inbox = try #require(library.state.addCollection(named: "Inbox", existing: []))
            let board = pasteboard()
            let defaults = ThrowawayDefaults.make()
            defaults.set(true, for: Setting.addsCopiesOnOpen)
            defaults.set(inbox.id.uuidString, for: Setting.defaultPasteCollectionID)
            board.string = "auto added into inbox"

            await library.state.clipboardDidBecomeActive(pasteboard: board, defaults: defaults)
            try await library.refreshed()

            let autoItem = try #require(library.store.items.first { $0.displayPreviewText == "auto added into inbox" })
            #expect(autoItem.collectionID == inbox.id)

            let provider = NSItemProvider(object: "offered into inbox" as NSString)
            await library.state.takeClipboardOffer([provider], defaults: defaults)
            try await library.refreshed()

            let offeredItem = try #require(library.store.items.first { $0.displayPreviewText == "offered into inbox" })
            #expect(offeredItem.collectionID == inbox.id)
        }

        @Test("automatic open capture suppresses empty-clipboard problem notices while manual adds report them")
        func whenAddingNilOrUnreadable_thenOnlyManualReportsEmpty() async throws {
            let library = try await MobileTestLibrary()

            let silent = await library.state.add(nil, reportEmpty: false)
            #expect(!silent)
            #expect(library.state.notice == nil)

            let board = pasteboard()
            let defaults = ThrowawayDefaults.make()
            defaults.set(true, for: Setting.addsCopiesOnOpen)
            board.items = [["com.copypesto.unsupported": Data([0x01, 0x02])]]
            await library.state.clipboardDidBecomeActive(pasteboard: board, defaults: defaults)
            #expect(library.state.notice == nil)

            let manual = await library.state.add(nil)
            #expect(!manual)
            #expect(library.state.notice?.text == "There was nothing Pesto can keep.")
        }
    }
}
