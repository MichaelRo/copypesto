// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("The AutoFill tip is offered once, after the first clip is kept, and never while the lock is on", .serialized)
@MainActor
struct MobileAutoFillTipTests {
    private func state(_ defaults: UserDefaults) -> MobileAppState {
        let state = MobileAppState(
            historyLock: MobileHistoryLock(
                authenticator: StubUserAuthenticator(available: true, grants: true), grace: AuthenticationGrace(),
                isEnabled: { defaults.value(for: Setting.biometricLockEnabled) }
            )
        )
        state.quickInsert = nil
        state.widget = nil
        return state
    }

    @Test("the first pin or snippet offers the tip, and the next one does not")
    func whenAClipIsKept_thenTheTipShowsOnce() {
        let defaults = ThrowawayDefaults.make()
        let state = state(defaults)

        state.clipWasKept(defaults: defaults, isLive: true)
        #expect(state.offersAutoFillTip)
        #expect(defaults.value(for: Setting.autoFillTipShown))

        state.dismissAutoFillTip()
        state.clipWasKept(defaults: defaults, isLive: true)
        #expect(!state.offersAutoFillTip)
    }

    @Test("a test or UI-test launch offers nothing unless it asks for the tip")
    func whenNotLive_thenNoTipUnlessAsked() {
        let defaults = ThrowawayDefaults.make()
        let state = state(defaults)

        state.clipWasKept(defaults: defaults, isLive: false)
        #expect(!state.offersAutoFillTip)

        defaults.set(true, for: Setting.uitestShowsAutoFillTip)
        state.clipWasKept(defaults: defaults, isLive: false)
        #expect(state.offersAutoFillTip)
    }

    @Test("with the History Lock on there is no tip, and it is not used up")
    func whenLocked_thenNoTip() {
        let defaults = ThrowawayDefaults.make()
        defaults.set(true, for: Setting.biometricLockEnabled)
        let state = state(defaults)

        state.clipWasKept(defaults: defaults, isLive: true)

        #expect(!state.offersAutoFillTip)
        #expect(!defaults.value(for: Setting.autoFillTipShown))
    }

    @Test("turning the lock on takes the tip away")
    func whenTheLockComesOn_thenTheTipGoes() {
        let defaults = ThrowawayDefaults.make()
        let state = state(defaults)
        state.clipWasKept(defaults: defaults, isLive: true)

        defaults.set(true, for: Setting.biometricLockEnabled)
        state.historyLockSettingChanged()

        #expect(!state.offersAutoFillTip)
    }

    @Test("a person who already saw the tip is not told about it again")
    func whenTipAlreadyShown_thenNoTip() {
        let defaults = ThrowawayDefaults.make()
        defaults.set(true, for: Setting.autoFillTipShown)
        let state = state(defaults)

        state.clipWasKept(defaults: defaults, isLive: true)

        #expect(!state.offersAutoFillTip)
    }

    @Test("Turn On switches Pesto's AutoFill setting on and then opens iOS's AutoFill settings")
    func whenTurnedOn_thenSettingOnAndSettingsOpen() async {
        let defaults = ThrowawayDefaults.make()
        let state = state(defaults)
        var opened = 0
        state.opensAutoFillSettings = { opened += 1 }
        state.clipWasKept(defaults: defaults, isLive: true)

        await state.turnOnAutoFillFromTip(defaults: defaults)

        #expect(defaults.value(for: Setting.quickInsertEnabled))
        #expect(opened == 1)
        #expect(!state.offersAutoFillTip)
    }

    @Test("Not Now closes the tip without clearing any settings")
    func whenDismissed_thenNothingChanges() {
        let defaults = ThrowawayDefaults.make()
        let state = state(defaults)
        state.clipWasKept(defaults: defaults, isLive: true)

        state.dismissAutoFillTip()

        #expect(!state.offersAutoFillTip)
        #expect(defaults.value(for: Setting.autoFillTipShown))
    }

    @Test("Set Up closes the tip and opens Keyboard & AutoFill setup")
    func whenSetUpChosen_thenTipDismissesAndSetupOpens() {
        let defaults = ThrowawayDefaults.make()
        let state = state(defaults)
        let library = LibraryModel()
        state.clipWasKept(defaults: defaults, isLive: true)

        state.dismissAutoFillTip()
        library.showsQuickInsertSetup = true

        #expect(!state.offersAutoFillTip)
        #expect(library.showsQuickInsertSetup)
        #expect(defaults.value(for: Setting.autoFillTipShown))
    }
}
