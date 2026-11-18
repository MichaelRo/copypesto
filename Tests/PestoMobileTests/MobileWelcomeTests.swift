// SPDX-License-Identifier: MIT
import Foundation
import LocalAuthentication
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("The iPhone and iPad welcome is shown once, and asks for nothing the person cannot see", .serialized)
@MainActor
struct MobileWelcomeTests {
    private func state(
        _ defaults: UserDefaults, grants: Bool = true, available: Bool = true
    )
    -> MobileAppState {
        let state = MobileAppState(
            historyLock: MobileHistoryLock(
                authenticator: StubUserAuthenticator(available: available, grants: grants), grace: AuthenticationGrace(),
                isEnabled: { defaults.value(for: Setting.biometricLockEnabled) }
            )
        )
        state.quickInsert = nil
        state.widget = nil
        return state
    }

    @Test("a first launch shows the welcome once, and a second launch does not")
    func whenFirstLaunch_thenShownOnce() {
        let defaults = ThrowawayDefaults.make()
        let state = state(defaults)

        state.presentWelcomeOnFirstLaunch(defaults: defaults, isLive: true)
        #expect(state.showsWelcome)
        #expect(defaults.value(for: Setting.welcomeShown))

        state.closeWelcome()
        state.presentWelcomeOnFirstLaunch(defaults: defaults, isLive: true)
        #expect(!state.showsWelcome)
    }

    @Test("a test or UI-test launch shows nothing unless it asks for the welcome")
    func whenNotLive_thenNotShownUnlessAsked() {
        let defaults = ThrowawayDefaults.make()
        let state = state(defaults)

        state.presentWelcomeOnFirstLaunch(defaults: defaults, isLive: false)
        #expect(!state.showsWelcome)
        #expect(!defaults.value(for: Setting.welcomeShown))

        defaults.set(true, for: Setting.uitestShowsWelcome)
        state.presentWelcomeOnFirstLaunch(defaults: defaults, isLive: false)
        #expect(state.showsWelcome)
    }

    @Test("a locked history shows no welcome and keeps it for the first unlocked launch")
    func whenLocked_thenNotShownAndNotUsedUp() {
        let defaults = ThrowawayDefaults.make()
        defaults.set(true, for: Setting.biometricLockEnabled)
        let state = state(defaults)

        state.presentWelcomeOnFirstLaunch(defaults: defaults, isLive: true)

        #expect(!state.showsWelcome)
        #expect(!defaults.value(for: Setting.welcomeShown))
    }

    @Test("Show Welcome Again shows it with the stored values and applies no default")
    func whenShownAgain_thenValuesUntouched() {
        let defaults = ThrowawayDefaults.make()
        defaults.set(true, for: Setting.welcomeShown)
        defaults.set(false, for: Setting.linkPreviews)
        let state = state(defaults)

        state.requestWelcomeAgain()
        #expect(state.takeWelcomeAgainRequest())
        #expect(!state.takeWelcomeAgainRequest())
        state.showWelcomeAgain()
        let model = WelcomeModel(defaults: defaults)
        model.goToNextStep()

        #expect(state.showsWelcome)
        #expect(!defaults.value(for: Setting.linkPreviews))
    }

    @Test("link previews are switched on when step two appears, and not before")
    func whenStepTwoAppears_thenLinkPreviewsOn() {
        let defaults = ThrowawayDefaults.make()
        let model = WelcomeModel(defaults: defaults)
        #expect(model.step == .keep)
        #expect(!defaults.hasValue(for: Setting.linkPreviews))

        model.goToNextStep()

        #expect(model.step == .choices)
        #expect(defaults.value(for: Setting.linkPreviews))
    }

    @Test("a welcome skipped on step one leaves link previews off and unset")
    func whenSkippedOnStepOne_thenLinkPreviewsStayOff() {
        let defaults = ThrowawayDefaults.make()
        let state = state(defaults)
        let model = WelcomeModel(defaults: defaults)
        state.presentWelcomeOnFirstLaunch(defaults: defaults, isLive: true)

        state.closeWelcome()

        #expect(model.step == .keep)
        #expect(!defaults.hasValue(for: Setting.linkPreviews))
        #expect(!defaults.value(for: Setting.linkPreviews))
    }

    @Test("a stored answer is never overwritten, however often step two appears")
    func whenAnAnswerIsStored_thenStepTwoKeepsIt() {
        let defaults = ThrowawayDefaults.make()
        defaults.set(false, for: Setting.linkPreviews)
        let model = WelcomeModel(defaults: defaults)
        model.goToNextStep()
        #expect(!defaults.value(for: Setting.linkPreviews))

        defaults.set(true, for: Setting.linkPreviews)
        model.goToPreviousStep()
        defaults.set(false, for: Setting.linkPreviews)
        model.goToNextStep()
        #expect(!defaults.value(for: Setting.linkPreviews))
    }

    @Test("the steps run keep, choices, sync, and stop at both ends")
    func whenSteppingThrough_thenTheOrderHolds() {
        let model = WelcomeModel(defaults: ThrowawayDefaults.make())
        model.goToPreviousStep()
        #expect(model.step == .keep)
        model.goToNextStep()
        model.goToNextStep()
        #expect(model.step == .sync)
        model.goToNextStep()
        #expect(model.step == .sync)
        model.goToPreviousStep()
        #expect(model.step == .choices)
    }

    @Test("turning the lock on asks first, and a refusal leaves it off")
    func whenAuthenticationIsRefused_thenTheLockStaysOff() async {
        let defaults = ThrowawayDefaults.make()
        let state = state(defaults, grants: false)

        let turnedOn = await state.turnOnHistoryLock(defaults: defaults)

        #expect(!turnedOn)
        #expect(!defaults.value(for: Setting.biometricLockEnabled))
        #expect(!state.historyLock.isEnabled)
    }

    @Test("an accepted prompt turns the lock on, and a device that cannot authenticate cannot")
    func whenAuthenticationIsGranted_thenTheLockIsOn() async {
        let defaults = ThrowawayDefaults.make()
        let granted = state(defaults)
        #expect(await granted.turnOnHistoryLock(defaults: defaults))
        #expect(defaults.value(for: Setting.biometricLockEnabled))

        let other = ThrowawayDefaults.make()
        let unavailable = state(other, available: false)
        #expect(await !unavailable.turnOnHistoryLock(defaults: other))
        #expect(!other.value(for: Setting.biometricLockEnabled))
    }

    @Test("Turn On Sync asks the library to open the flow once, and Not Now or Skip asks for nothing")
    func whenTurnOnSyncIsChosen_thenOneRequestIsLeft() {
        let state = state(ThrowawayDefaults.make())

        state.closeWelcome()
        #expect(!state.takeSyncSetUpRequest())

        state.closeWelcome(startingSync: true)
        #expect(!state.showsWelcome)
        #expect(state.takeSyncSetUpRequest())
        #expect(!state.takeSyncSetUpRequest())
    }

    @Test("the lock caption follows the device's biometry and keeps its promise about widgets and AutoFill")
    func whenBiometryDiffers_thenTheCaptionFollows() {
        let face = DeviceAuthenticationWords.lockCaption(for: .faceID)
        let touch = DeviceAuthenticationWords.lockCaption(for: .touchID)
        let none = DeviceAuthenticationWords.lockCaption(for: .none)

        #expect(face.hasPrefix("Face ID before your clips show."))
        #expect(touch.hasPrefix("Touch ID before your clips show."))
        #expect(none.hasPrefix("Your passcode before your clips show."))
        #expect([face, touch, none].allSatisfy { $0.hasSuffix("Widgets and AutoFill stay empty while it\u{2019}s on.") })
    }

    @Test("the welcome's markers are registered per device and start off")
    func whenRegistered_thenMarkersStartOff() {
        for key in [Setting.welcomeShown, Setting.autoFillTipShown] {
            #expect(key.defaultValue == false)
            #expect(Setting.allNames.contains(key.name))
        }
    }
}
