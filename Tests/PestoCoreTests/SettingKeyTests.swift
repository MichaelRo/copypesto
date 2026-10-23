// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("SettingKey")
struct SettingKeyTests {
    private func defaults() -> UserDefaults {
        ThrowawayDefaults.make()
    }

    @Test("an unset key reads as its default, with nothing registered")
    func whenUnset_thenTheDefault() {
        let store = defaults()

        #expect(store.value(for: Setting.retentionDays) == 30)
        #expect(store.value(for: Setting.pinnedWindowAutoPaste) == true)
        #expect(store.value(for: Setting.doubleCopyAppend) == false)
        #expect(Setting.doubleCopyAppend.defaultValue == false)
        #expect(store.value(for: Setting.cardSize) == "large")
        #expect(!store.hasValue(for: Setting.retentionDays))
    }

    @Test("a stored value is read back, and removing it returns the key to its default")
    func whenSetAndRemoved_thenRoundTrips() {
        let store = defaults()

        store.set(90, for: Setting.retentionDays)
        store.set(false, for: Setting.pinnedWindowAutoPaste)
        store.set("small", for: Setting.cardSize)

        #expect(store.value(for: Setting.retentionDays) == 90)
        #expect(store.value(for: Setting.pinnedWindowAutoPaste) == false)
        #expect(store.value(for: Setting.cardSize) == "small")
        #expect(store.hasValue(for: Setting.retentionDays))

        store.removeValue(for: Setting.retentionDays)
        #expect(store.value(for: Setting.retentionDays) == 30)
    }

    @Test("a value of another type reads as unset instead of becoming a surprising one")
    func whenTheTypeIsWrong_thenTheDefault() {
        let store = defaults()
        store.set("not a number", forKey: Setting.retentionDays.name)
        store.set(7, forKey: Setting.cardSize.name)
        store.set("yes", forKey: Setting.clearOnQuit.name)

        #expect(store.value(for: Setting.retentionDays) == 30)
        #expect(store.value(for: Setting.cardSize) == "large")
        #expect(store.value(for: Setting.clearOnQuit) == false)
    }

    @Test("a Bool or a fractional number stored under a whole-number key reads as unset")
    func whenANumberKeyHoldsABoolOrAFraction_thenTheDefault() {
        let store = defaults()
        store.set(true, forKey: Setting.retentionDays.name)
        #expect(store.value(for: Setting.retentionDays) == 30)

        store.set(2.7, forKey: Setting.retentionDays.name)
        #expect(store.value(for: Setting.retentionDays) == 30)

        store.set(14, forKey: Setting.retentionDays.name)
        #expect(store.value(for: Setting.retentionDays) == 14)
    }

    @Test("retention is spelled once: the setting's default is the policy's default")
    func whenRetentionDefaults_thenTheyAgreeWithThePolicy() {
        let policy = RetentionPolicy.fromDefaults(defaults())

        #expect(policy == RetentionPolicy.default)
        #expect(Setting.retentionDays.defaultValue == Int(RetentionPolicy.default.maxAge / 86_400))
        #expect(Setting.retentionMaxItems.defaultValue == RetentionPolicy.default.maxItemCount)
    }

    @Test("no two settings share a name")
    func whenListed_thenNamesAreUnique() {
        #expect(Set(Setting.allNames).count == Setting.allNames.count)
        #expect(Setting.allNames.allSatisfy { !$0.isEmpty })
    }

    @Test("the policies that own a key and the registry agree on its name")
    func whenAPolicyOwnsAKey_thenTheRegistryUsesIt() {
        #expect(Setting.nsfwMode.name == NSFWMode.defaultsKey)
        #expect(Setting.linkPreviews.name == LinkPreviewPolicy.defaultsKey)
        #expect(Setting.soundEffects.name == SoundEffectPolicy.defaultsKey)
        #expect(Setting.searchHistory.name == SearchHistory.defaultsKey)
        #expect(Setting.doubleCopyAppend.name == DoubleCopyPolicy.defaultsKey)
        #expect(Setting.appleIntelligenceEnabled.name == AIAvailability.enabledDefaultsKey)
        #expect(Setting.authenticationGraceMinutes.name == AuthenticationGrace.minutesKey)
    }
}
