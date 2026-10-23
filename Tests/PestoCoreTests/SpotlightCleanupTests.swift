// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

private final class RecordingIndex: SpotlightIndexRemoving, @unchecked Sendable {
    private(set) var removedDomains: [[String]] = []

    func removeDomains(_ domains: [String]) {
        removedDomains.append(domains)
    }
}

@Suite("SpotlightCleanup: clips are no longer put into Spotlight, and what an older version put there is removed once")
struct SpotlightCleanupTests {
    @Test("the index Pesto made, under the current and the old identity, is removed")
    func removesBothDomains() {
        let defaults = ThrowawayDefaults.make()
        let index = RecordingIndex()

        SpotlightCleanup.removeIndexOnce(defaults: defaults, index: index)

        #expect(index.removedDomains == [["\(AppIdentity.bundleID).clips", AppIdentity.legacySpotlightDomain]])
    }

    @Test("it runs once, so a later launch does not touch the index again")
    func runsOnce() {
        let defaults = ThrowawayDefaults.make()
        let index = RecordingIndex()

        SpotlightCleanup.removeIndexOnce(defaults: defaults, index: index)
        SpotlightCleanup.removeIndexOnce(defaults: defaults, index: index)

        #expect(index.removedDomains.count == 1)
    }

    @Test("the switch an older version stored, and the date it was turned on, are forgotten")
    func forgetsTheOldPreferences() {
        let defaults = ThrowawayDefaults.make()
        defaults.set(true, forKey: SpotlightCleanup.legacyEnabledKey)
        defaults.set(Date.now, forKey: SpotlightCleanup.legacyEnabledAtKey)

        SpotlightCleanup.removeIndexOnce(defaults: defaults, index: RecordingIndex())

        #expect(defaults.object(forKey: SpotlightCleanup.legacyEnabledKey) == nil)
        #expect(defaults.object(forKey: SpotlightCleanup.legacyEnabledAtKey) == nil)
    }
}
