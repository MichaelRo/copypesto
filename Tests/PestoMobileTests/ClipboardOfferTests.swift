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
            AppDefaults.store.set(false, for: Setting.addsCopiesOnOpen)
            board.string = "copied in Safari"

            await library.state.clipboardDidBecomeActive(pasteboard: board)
            #expect(library.state.clipboardOfferCount == board.changeCount)
            try await library.refreshed()
            #expect(!library.store.items.contains { $0.displayPreviewText == "copied in Safari" }, "nothing was read")

            library.state.dismissClipboardOffer()
            await library.state.clipboardDidBecomeActive(pasteboard: board)
            #expect(library.state.clipboardOfferCount == nil, "the same change is not offered twice")

            MobileClipboard.write(.text("copied from Pesto"), protected: false, to: board)
            await library.state.clipboardDidBecomeActive(pasteboard: board)
            #expect(library.state.clipboardOfferCount == nil, "Pesto's own copy is not offered")
        }

        @Test("with adding on, the change is read and added through the capture path, marked as pasted")
        func whenAddingIsOn_thenItIsAdded() async throws {
            let library = try await MobileTestLibrary()
            let board = pasteboard()
            AppDefaults.store.set(true, for: Setting.addsCopiesOnOpen)
            defer { AppDefaults.store.set(false, for: Setting.addsCopiesOnOpen) }
            board.string = "added on open"

            await library.state.clipboardDidBecomeActive(pasteboard: board)
            try await library.refreshed()

            #expect(library.state.clipboardOfferCount == nil)
            #expect(library.store.items
                .contains { $0.displayPreviewText == "added on open" && $0.captureMethod == .paste })
        }
    }
}
