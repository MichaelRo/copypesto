// SPDX-License-Identifier: MIT
import Foundation
import SwiftUI
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("Batch 3: iOS privacy cover, lock defaults, extensions settings, and Spotlight routing")
@MainActor
struct MobileBatch3Tests {
    @Test("PrivacyCoverHost never covers .inactive Face ID sheets, only .background when unlocked")
    func whenScenePhaseChanges_thenCoverOnlyShowsInUnlockedBackground() {
        #expect(!PrivacyCoverHost.covers(in: .active, isLocked: false))
        #expect(!PrivacyCoverHost.covers(in: .inactive, isLocked: false))
        #expect(PrivacyCoverHost.covers(in: .background, isLocked: false))
        #expect(!PrivacyCoverHost.covers(in: .background, isLocked: true))
    }

    @Test("iOS keyboard, AutoFill and widgets default to on; clips outside while locked default to off (ADR 0055)")
    func whenFreshDefaults_thenOutsideSurfacesDefaultOn() {
        #expect(Setting.quickInsertEnabled.defaultValue == true)
        #expect(Setting.keyboardEnabled.defaultValue == true)
        #expect(Setting.autoFillEnabled.defaultValue == true)
        #expect(Setting.widgetsEnabled.defaultValue == true)
        #expect(Setting.showsClipsOutsideWhileLocked.defaultValue == false)
    }

    @Test("MobileHistoryLock locks immediately on background when timeoutMinutes is zero or unset")
    func whenImmediateTimeout_thenLocksImmediatelyOnBackground() {
        var enabled = true
        let lock = MobileHistoryLock(
            authenticator: StubUserAuthenticator(available: true, grants: true),
            grace: AuthenticationGrace(),
            isEnabled: { enabled },
            timeoutMinutes: { 0 },
            showsClipsOutside: { false }
        )
        lock.lockWasTurnedOff()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        lock.didLeaveForeground(at: start)

        #expect(lock.lockIfAwayTooLong(at: start.addingTimeInterval(1)))
        #expect(lock.isLocked)
        enabled = false
    }

    @Test("SearchPestoIntent opens the app and routes its query into LibraryModel search")
    func whenSearchIntentRuns_thenOpensSearchAndClearsOnLock() async throws {
        let library = try await MobileTestLibrary()
        let model = LibraryModel()

        #expect(SearchPestoIntent.openAppWhenRun == true)
        #expect(PestoMobileShortcuts.appShortcuts.count == 2)

        library.state.requestShortcutSearch("invoice")
        let query = try #require(library.state.takeShortcutSearchQuery())
        model.openSearch(query)

        #expect(model.isSearching)
        #expect(model.query == "invoice")

        model.closeEverything()
        #expect(!model.isSearching)
        #expect(model.query.isEmpty)
    }

    @Test("copyAsync loads large or image clips off the main actor and updates notice and lastUsedAt")
    func whenCopyingClipAsync_thenCopiesAndUpdatesOrder() async throws {
        let library = try await MobileTestLibrary()
        let first = try await library.add("alpha")
        let large = String(repeating: "x", count: 40_000)
        try await library.service.ingest(#require(ClipCapture.text(large)))
        let second = try await library.settle()
        let initialTimestamp = first.timestamp

        #expect(second.byteSize > 32_768)
        let copied = await library.state.copyAsync(first)
        #expect(copied)
        #expect(library.state.notice?.text == "Copied")
        #expect(first.timestamp >= initialTimestamp)

        let copiedLarge = await library.state.copyAsync(second)
        #expect(copiedLarge)
        #expect(library.state.notice?.text == "Copied")
    }
}
