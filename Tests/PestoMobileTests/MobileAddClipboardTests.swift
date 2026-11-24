// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
import UIKit
@testable import PestoCore
@testable import PestoMobile

extension MobilePasteboardGlobals {
    @Suite("Add Clipboard to Pesto goes through the normal capture path")
    @MainActor
    struct MobileAddClipboardTests {
        @Test("the clipboard's text is ingested as a Shortcut clip, and the foreground offer is not repeated")
        func whenClipboardHasText_thenItIsAdded() async throws {
            let library = try await MobileTestLibrary()
            let board = AppPasteboard.general
            board.string = "copied in another app"
            let defaults = ThrowawayDefaults.make()

            try await library.state.addClipboardFromShortcut(pasteboard: board, defaults: defaults)
            try await library.refreshed()

            #expect(library.store.items.contains {
                $0.displayPreviewText == "copied in another app" && $0.captureMethod == .shortcut
            })
            #expect(defaults.value(for: Setting.lastSeenPasteboardChange) == board.changeCount)
            #expect(library.state.clipboardOfferCount == nil)
        }

        @Test("an empty clipboard says so, and a locked history adds nothing")
        func whenEmptyOrLocked_thenRefused() async throws {
            let library = try await MobileTestLibrary()
            let board = AppPasteboard.general
            board.items = []
            await #expect(throws: MobileAppState.ShortcutFailure.emptyClipboard) {
                try await library.state.addClipboardFromShortcut(pasteboard: board)
            }

            let locked = try await MobileTestLibrary(
                lock: MobileHistoryLock(
                    authenticator: StubUserAuthenticator(available: true, grants: true), grace: AuthenticationGrace(),
                    isEnabled: { true }
                )
            )
            board.string = "while locked"
            await #expect(throws: MobileAppState.ShortcutFailure.locked) {
                try await locked.state.addClipboardFromShortcut(pasteboard: board)
            }
            #expect(!locked.store.items.contains { $0.displayPreviewText == "while locked" })
        }

        @Test("MobileAppState conforms to ClipboardShortcutHandling for the intent")
        func whenInvokedThroughProtocol_thenClipboardIsAdded() async throws {
            let library = try await MobileTestLibrary()
            let board = AppPasteboard.general
            board.string = "via shortcut protocol"
            let handler: any ClipboardShortcutHandling = library.state

            try await handler.addClipboardFromShortcut()
            try await library.refreshed()

            #expect(library.store.items.contains {
                $0.displayPreviewText == "via shortcut protocol" && $0.captureMethod == .shortcut
            })
        }

        @Test(
            "a configured default paste collection receives shortcut pastes, and deleted or smart ones fall back to nil"
        )
        func whenDefaultPasteCollectionSet_thenShortcutUsesItWithSafeFallback() async throws {
            let library = try await MobileTestLibrary()
            let manual = try #require(library.state.addCollection(named: "Inbox", existing: []))
            let context = try #require(library.state.historyContainer?.mainContext)
            let smartData = try SmartCollectionPredicate.encodeRuleSet(PredicateRuleSet.snippets)
            let smart = Pinboard(
                name: "Smart", symbolName: "sparkles", colorHex: "#2F8B4C", sortOrder: 1,
                isSmart: true, smartPredicateData: smartData
            )
            context.insert(smart)
            try context.save()

            let defaults = ThrowawayDefaults.make()
            defaults.set(manual.id.uuidString, for: Setting.defaultPasteCollectionID)
            let board = AppPasteboard.general
            board.string = "into default collection"

            try await library.state.addClipboardFromShortcut(pasteboard: board, defaults: defaults)
            try await library.refreshed()
            let pasted = try #require(library.store.items.first { $0.displayPreviewText == "into default collection" })
            #expect(pasted.collectionID == manual.id)

            defaults.set(smart.id.uuidString, for: Setting.defaultPasteCollectionID)
            #expect(library.state.resolvedDefaultPasteCollectionID(defaults: defaults) == nil)

            defaults.set(UUID().uuidString, for: Setting.defaultPasteCollectionID)
            #expect(library.state.resolvedDefaultPasteCollectionID(defaults: defaults) == nil)

            defaults.set(manual.id.uuidString, for: Setting.defaultPasteCollectionID)
            await library.state.deleteCollection(manual.id)
            #expect(library.state.resolvedDefaultPasteCollectionID(defaults: defaults) == nil)
        }
    }
}
