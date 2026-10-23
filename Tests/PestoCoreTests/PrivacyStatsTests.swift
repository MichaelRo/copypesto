// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Privacy counters")
struct PrivacyStatsTests {
    private func suite() -> UserDefaults {
        ThrowawayDefaults.make()
    }

    @Test("nothing recorded yet reads as zero")
    func whenNew_thenZero() {
        let stats = PrivacyStatsStore(defaults: suite()).stats
        #expect(stats.excludedAppBlocks == 0 && stats.concealedBlocks == 0)
    }

    @Test("each kind of block is counted separately and survives a restart")
    func whenRecorded_thenCountedAndPersisted() {
        let defaults = suite()
        let store = PrivacyStatsStore(defaults: defaults)
        store.record(.excludedApp)
        store.record(.excludedApp)
        store.record(.concealedMarker)

        let reloaded = PrivacyStatsStore(defaults: defaults).stats
        #expect(reloaded.excludedAppBlocks == 2)
        #expect(reloaded.concealedBlocks == 1)
        #expect(reloaded.total == 3)
    }

    @Test("the counting period starts with the first block, and resetting clears the counts")
    func whenFirstBlock_thenSinceIsSet_andResetClears() {
        let store = PrivacyStatsStore(defaults: suite())
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(store.stats.since == nil)

        store.record(.concealedMarker, now: start)
        store.record(.concealedMarker, now: start.addingTimeInterval(500))
        #expect(store.stats.since == start)

        store.reset()
        #expect(store.stats.total == 0 && store.stats.since == nil)
    }

    @Test("only counts are stored, never what was copied")
    func whenStored_thenNoContentKeys() throws {
        let defaults = suite()
        PrivacyStatsStore(defaults: defaults).record(.excludedApp)
        let raw = try #require(defaults.data(forKey: PrivacyStatsStore.defaultsKey))
        let text = try #require(String(bytes: raw, encoding: .utf8))
        #expect(text.contains("excludedAppBlocks"))
        #expect(!text.contains("com."), "an app identifier must not be stored")
    }

    @Test("a copy from an excluded app, or carrying a concealed marker, is blocked for the matching reason")
    func whenBlocked_thenReason() {
        let rules = ExclusionRules()
        #expect(rules.blockReason(typeIdentifiers: [], frontmostBundleID: "com.1password.1password") == .excludedApp)
        #expect(rules.blockReason(
            typeIdentifiers: ["org.nspasteboard.ConcealedType"],
            frontmostBundleID: "com.example.x"
        ) == .concealedMarker)
        #expect(rules
            .blockReason(typeIdentifiers: ["public.utf8-plain-text"], frontmostBundleID: "com.example.x") == nil)
        #expect(rules.blockReason(
            typeIdentifiers: ["org.nspasteboard.ConcealedType"],
            frontmostBundleID: "com.1password.1password"
        ) == .excludedApp)
    }
}
