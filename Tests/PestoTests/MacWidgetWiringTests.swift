// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import Testing
@testable import Pesto

@Suite("The Mac widget is kept only by a build signed for it")
@MainActor
struct MacWidgetWiringTests {
    @Test("a development or test build has no widget target, so it opens no group container and asks no Keychain")
    func whenNotSignedForTheWidget_thenThereIsNoTarget() {
        #expect(WidgetSharing.current == nil)
        #expect(MacWidgetTarget.current == nil)
        #expect(AppPaths.sharedGroupDirectory.map { $0.path.contains("Group Containers") } != true)
    }

    @Test("the cover's callback runs once per change of either cover, never for an unchanged value")
    func whenTheCoverChanges_thenTheWidgetIsTold() {
        let state = AppState()
        var calls = 0
        state.onContentCoverChanged = { calls += 1 }

        state.isContentHiddenManually = true
        state.isContentHiddenManually = true
        state.isScreenBeingShared = true
        state.isScreenBeingShared = false
        state.isContentHiddenManually = false

        #expect(calls == 4)
    }
}
