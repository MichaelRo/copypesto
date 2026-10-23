// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Preference keys that other types read from Setting")
struct SettingLiteralKeysTests {
    @Test("the stored names are the ones earlier builds wrote")
    func whenRead_thenNamesAreUnchanged() {
        #expect(Setting.retentionDays.name == "retentionDays")
        #expect(Setting.retentionMaxItems.name == "retentionMaxItems")
        #expect(Setting.doubleCopyAppend.name == "doubleCopyAppendEnabled")
        #expect(Setting.nsfwMode.name == "nsfwMode")
        #expect(Setting.biometricLockTimeoutMinutes.name == "biometricLockTimeoutMinutes")
        #expect(Setting.authenticationGraceMinutes.name == "authenticationGraceMinutes")
        #expect(Setting.appleIntelligenceEnabled.name == "appleIntelligenceEnabled")
        #expect(Setting.searchHistory.name == "searchHistory")
        #expect(Setting.authenticationWindowMigrated.name == "authenticationWindowMigrated")
        #expect(Setting.spotlightIndexRemoved.name == "spotlightIndexRemoved")
    }

    @Test("the types that used to own a key and a default still agree with the registry")
    func whenTypesReadTheRegistry_thenTheyAgree() {
        #expect(DoubleCopyPolicy.defaultsKey == Setting.doubleCopyAppend.name)
        #expect(NSFWMode.defaultsKey == Setting.nsfwMode.name)
        #expect(Setting.nsfwMode.defaultValue == NSFWMode.blur.rawValue)
        #expect(SearchHistory.defaultsKey == Setting.searchHistory.name)
        #expect(SpotlightCleanup.doneKey == Setting.spotlightIndexRemoved.name)
        #expect(AIAvailability.enabledDefaultsKey == Setting.appleIntelligenceEnabled.name)
        #expect(AuthenticationGrace.minutesKey == Setting.authenticationGraceMinutes.name)
        #expect(AuthenticationGrace.defaultMinutes == 5)
        #expect(AuthenticationWindowMigration.doneKey == Setting.authenticationWindowMigrated.name)
        #expect(HistoryLockPolicy.defaultTimeoutMinutes == 5)
    }

    @Test("the default retention is 30 days and 5,000 clips, as shipped")
    func whenDefaultRetention_thenAsShipped() {
        #expect(RetentionPolicy.default.maxAge == 30 * 24 * 60 * 60)
        #expect(RetentionPolicy.default.maxItemCount == 5000)
    }
}
