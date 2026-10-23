// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("Answering the import offer", .serialized)
    @MainActor
    struct ImportOfferAnswerTests {
        private func state(offering sources: [ImportSource]) -> AppState {
            let state = AppState()
            state.importOffer = sources
            return state
        }

        private func resetOffer() {
            AppDefaults.store.removeObject(forKey: Setting.importOffered.name)
        }

        @Test("the installed apps are found for the Settings card without waiting for a view to ask")
        func whenRefreshed_thenInstalledAppsAreKnown() {
            let state = AppState()
            state.clipboardAppDetector = FixtureAppDetector(fixture: "paste,maccy")
            #expect(state.installedImportSources.isEmpty)

            state.refreshInstalledImportSources()

            #expect(state.installedImportSources == [.paste, .maccy])
        }

        @Test("accepting with one app starts that app's import in Settings, Data")
        func whenOneApp_thenImportStarts() {
            defer { resetOffer() }
            let state = state(offering: [.maccy])
            var opened = 0
            state.openSettingsFromOverlay = { opened += 1 }

            state.answerImportOffer(accepted: true)

            #expect(state.pendingImportSource == .maccy)
            #expect(state.pendingSettingsRow == nil)
            #expect(state.pendingSettingsSection == SettingsSection.data.rawValue)
            #expect(state.importOffer.isEmpty)
            #expect(opened == 1)
        }

        @Test("accepting with several apps shows the Found on this Mac card and starts no import")
        func whenSeveralApps_thenCardShownAndNothingStarts() {
            defer { resetOffer() }
            let state = state(offering: [.paste, .maccy])
            state.openSettingsFromOverlay = {}

            state.answerImportOffer(accepted: true)

            #expect(state.pendingImportSource == nil, "each import keeps its own consent")
            #expect(state.pendingSettingsRow == SettingsIndex.foundOnThisMacTitle)
            #expect(state.pendingSettingsSection == SettingsSection.data.rawValue)
        }

        @Test("Not now ends the offer for every app and opens nothing")
        func whenDeclined_thenEndedForGood() {
            defer { resetOffer() }
            let state = state(offering: [.paste, .maccy])
            var opened = 0
            state.openSettingsFromOverlay = { opened += 1 }

            state.answerImportOffer(accepted: false)

            #expect(state.importOffer.isEmpty)
            #expect(AppDefaults.store.value(for: Setting.importOffered))
            #expect(state.pendingImportSource == nil && state.pendingSettingsRow == nil)
            #expect(opened == 0)
        }
    }
}
