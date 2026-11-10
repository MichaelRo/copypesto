// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Setup opens with link previews and other devices' copies on, once, for a new install")
struct OnboardingDefaultsTests {
    @Test("a new install gets both on")
    func whenFirstRun_thenBothOn() {
        let defaults = ThrowawayDefaults.make()

        OnboardingDefaults.applyOnce(defaults: defaults, isLive: true)

        #expect(defaults.value(for: Setting.linkPreviews))
        #expect(defaults.value(for: Setting.keepsRemoteCopies))
        #expect(defaults.value(for: Setting.onboardingDefaultsOffered))
    }

    @Test("a person who finished setup before this existed is never switched on")
    func whenAlreadyOnboarded_thenNothingChanges() {
        let defaults = ThrowawayDefaults.make()
        defaults.set(true, for: Setting.hasOnboarded)

        OnboardingDefaults.applyOnce(defaults: defaults, isLive: true)

        #expect(!defaults.value(for: Setting.linkPreviews))
        #expect(!defaults.value(for: Setting.keepsRemoteCopies))
        #expect(defaults.value(for: Setting.onboardingDefaultsOffered))
    }

    @Test("the answer is the person's after the first offer, so switching off sticks")
    func whenOfferedBefore_thenAnswerKept() {
        let defaults = ThrowawayDefaults.make()
        OnboardingDefaults.applyOnce(defaults: defaults, isLive: true)
        defaults.set(false, for: Setting.linkPreviews)
        defaults.set(false, for: Setting.keepsRemoteCopies)

        OnboardingDefaults.applyOnce(defaults: defaults, isLive: true)

        #expect(!defaults.value(for: Setting.linkPreviews))
        #expect(!defaults.value(for: Setting.keepsRemoteCopies))
    }

    @Test("a test or UI-test launch changes nothing")
    func whenNotLive_thenNothingChanges() {
        let defaults = ThrowawayDefaults.make()

        OnboardingDefaults.applyOnce(defaults: defaults, isLive: false)

        #expect(!defaults.value(for: Setting.linkPreviews))
        #expect(!defaults.value(for: Setting.onboardingDefaultsOffered))
    }

    @Test("the offer flag is a per-Mac marker: registered, not exported, and off to start with")
    func whenRegistered_thenPerMacMarker() {
        #expect(Setting.onboardingDefaultsOffered.name == "onboardingDefaultsOffered")
        #expect(Setting.onboardingDefaultsOffered.defaultValue == false)
        #expect(Setting.allNames.contains(Setting.onboardingDefaultsOffered.name))
        #expect(!SettingsBackupManager.backupKeys.contains(Setting.onboardingDefaultsOffered.name))
    }

    @Test("everywhere else the settings still start off, so only setup turns them on")
    func whenNoSetup_thenDefaultsStayOff() {
        #expect(Setting.linkPreviews.defaultValue == false)
        #expect(Setting.keepsRemoteCopies.defaultValue == false)
    }

    @Test("an explicit setting restored or imported before setup finishes is never overwritten")
    func whenValueAlreadyStored_thenNotOverwritten() {
        let defaults = ThrowawayDefaults.make()
        defaults.set(false, for: Setting.linkPreviews)

        OnboardingDefaults.applyOnce(defaults: defaults, isLive: true)

        #expect(!defaults.value(for: Setting.linkPreviews))
        #expect(defaults.value(for: Setting.keepsRemoteCopies))
    }

    @Test("calling applyOnce twice leaves the store unchanged the second time")
    func whenCalledTwice_thenIdempotent() {
        let defaults = ThrowawayDefaults.make()

        OnboardingDefaults.applyOnce(defaults: defaults, isLive: true)
        defaults.set(false, for: Setting.linkPreviews)
        OnboardingDefaults.applyOnce(defaults: defaults, isLive: true)

        #expect(!defaults.value(for: Setting.linkPreviews))
        #expect(defaults.value(for: Setting.keepsRemoteCopies))
    }
}
