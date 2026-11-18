// SPDX-License-Identifier: MIT
import Foundation
import Testing
import UIKit
@testable import PestoCore
@testable import PestoMobile

@Suite("Add Clipboard to Pesto goes through the normal capture path")
@MainActor
struct MobileAddClipboardTests {
    @Test("the clipboard's text is ingested as a Shortcut clip, and the foreground offer is not repeated")
    func whenClipboardHasText_thenItIsAdded() async throws {
        let library = try await MobileTestLibrary()
        let board = AppPasteboard.general
        board.string = "copied in another app"

        try await library.state.addClipboardFromShortcut(pasteboard: board)
        try await library.refreshed()

        #expect(library.store.items.contains {
            $0.displayPreviewText == "copied in another app" && $0.captureMethod == .shortcut
        })
        #expect(AppDefaults.store.value(for: Setting.lastSeenPasteboardChange) == board.changeCount)
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
}
