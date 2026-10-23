// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("RetentionPolicy + RetentionPruner")
struct RetentionPolicyTests {
    private let now = Date()

    @Test("default policy has 30 days / 5000 items / 2 GB")
    func defaultPolicy() {
        let p = RetentionPolicy.default
        #expect(p.maxAge == 30 * 86_400)
        #expect(p.maxItemCount == 5000)
        #expect(p.maxTotalBytes == 2 * 1024 * 1024 * 1024)
    }

    @Test("evicts items older than maxAge")
    func whenOlderThanMaxAge_thenEvict() {
        let policy = RetentionPolicy(maxAge: 60, maxItemCount: 1000, maxTotalBytes: 1_000_000_000)
        // swiftlint:disable:next large_tuple
        let candidates: [(UUID, Date, Int)] = [
            (UUID(), now.addingTimeInterval(-120), 100),
            (UUID(), now.addingTimeInterval(-30), 100),
            (UUID(), now.addingTimeInterval(-90), 100)
        ]
        let evictions = RetentionPruner.computeEvictions(candidates: candidates, policy: policy, now: now)
        // The -120 and -90 items are older than 60s — they should be evicted.
        #expect(Set(evictions) == Set([candidates[0].0, candidates[2].0]))
    }

    @Test("evicts to enforce maxItemCount when too many items")
    func whenTooManyItems_thenEvictOldestExcess() {
        let policy = RetentionPolicy(maxAge: 86_400, maxItemCount: 2, maxTotalBytes: 1_000_000_000)
        // 3 items, all within age, but max is 2 — should evict 1 (the oldest).
        // swiftlint:disable:next large_tuple
        let candidates: [(UUID, Date, Int)] = [
            (UUID(), now.addingTimeInterval(-300), 100),
            (UUID(), now.addingTimeInterval(-200), 100),
            (UUID(), now.addingTimeInterval(-100), 100)
        ]
        let evictions = RetentionPruner.computeEvictions(candidates: candidates, policy: policy, now: now)
        #expect(evictions.count == 1)
        #expect(evictions[0] == candidates[0].0)
    }

    @Test("evicts to enforce maxTotalBytes when over disk budget")
    func whenOverDiskBudget_thenEvictOldestUntilUnder() {
        let policy = RetentionPolicy(maxAge: 86_400, maxItemCount: 1000, maxTotalBytes: 200)
        // 3 × 100 byte items, but max is 200 — should evict 1.
        // swiftlint:disable:next large_tuple
        let candidates: [(UUID, Date, Int)] = [
            (UUID(), now.addingTimeInterval(-300), 100),
            (UUID(), now.addingTimeInterval(-200), 100),
            (UUID(), now.addingTimeInterval(-100), 100)
        ]
        let evictions = RetentionPruner.computeEvictions(candidates: candidates, policy: policy, now: now)
        #expect(evictions.count == 1)
        #expect(evictions[0] == candidates[0].0)
    }

    @Test("evicts nothing when all caps satisfied")
    func whenWithinCaps_thenNoEvictions() {
        let policy = RetentionPolicy(maxAge: 86_400, maxItemCount: 1000, maxTotalBytes: 1_000_000_000)
        // swiftlint:disable:next large_tuple
        let candidates: [(UUID, Date, Int)] = [
            (UUID(), now.addingTimeInterval(-100), 50)
        ]
        let evictions = RetentionPruner.computeEvictions(candidates: candidates, policy: policy, now: now)
        #expect(evictions.isEmpty)
    }
}

// MARK: - User settings (the retention settings were never read)

@Suite("RetentionPolicy from settings")
struct RetentionPolicySettingsTests {
    private func makeDefaults(_ test: String = #function) -> UserDefaults {
        // One suite per test: tests run in parallel and must not share preferences.
        ThrowawayDefaults.make("retention-policy-\(test.prefix(while: { $0 != "(" }))-\(UUID().uuidString)")
    }

    @Test("with no settings saved, the default policy applies")
    func whenNothingSaved_thenDefault() {
        #expect(RetentionPolicy.fromDefaults(makeDefaults()) == .default)
    }

    @Test("the saved days and item count set the age and count caps")
    func whenSaved_thenCapsFollowSettings() {
        let defaults = makeDefaults()
        defaults.set(365, forKey: "retentionDays")
        defaults.set(1000, forKey: "retentionMaxItems")

        let policy = RetentionPolicy.fromDefaults(defaults)

        #expect(policy.maxAge == 365 * 24 * 60 * 60)
        #expect(policy.maxItemCount == 1000)
        #expect(policy.maxTotalBytes == RetentionPolicy.default.maxTotalBytes)
    }

    @Test("zero days means keep forever, and then nothing is evicted for its age")
    func whenZeroDays_thenNoAgeLimit() {
        let defaults = makeDefaults()
        defaults.set(0, forKey: "retentionDays")
        let policy = RetentionPolicy.fromDefaults(defaults)
        #expect(policy.maxAge == .infinity)

        let now = Date()
        let ancient = (UUID(), now.addingTimeInterval(-20 * 365 * 86_400), 10)
        let evictions = RetentionPruner.computeEvictions(candidates: [ancient], policy: policy, now: now)
        #expect(evictions.isEmpty)
    }

    @Test("the choices offered in Settings are the ones the policy accepts, and a stored odd value is not a preset")
    func choices_matchThePolicy() {
        #expect(RetentionChoices.ageDays.contains(RetentionChoices.foreverDays))
        #expect(RetentionChoices.ageDays.filter { $0 != RetentionChoices.foreverDays }
            .allSatisfy { (1...365).contains($0) })
        #expect(RetentionChoices.itemCounts.allSatisfy { (100...10_000).contains($0) })
        #expect(RetentionChoices.isPresetAge(30))
        #expect(!RetentionChoices.isPresetAge(45))
        #expect(!RetentionChoices.isPresetCount(1234))
    }

    @Test("values outside the ranges the settings UI allows are clamped")
    func whenOutOfRange_thenClamped() {
        let defaults = makeDefaults()
        defaults.set(-5, forKey: "retentionDays")
        defaults.set(-5, forKey: "retentionMaxItems")
        #expect(RetentionPolicy.fromDefaults(defaults).maxAge == 1 * 24 * 60 * 60)
        #expect(RetentionPolicy.fromDefaults(defaults).maxItemCount == 100)

        defaults.set(100_000, forKey: "retentionDays")
        defaults.set(10_000_000, forKey: "retentionMaxItems")
        #expect(RetentionPolicy.fromDefaults(defaults).maxAge == 365 * 24 * 60 * 60)
        #expect(RetentionPolicy.fromDefaults(defaults).maxItemCount == 10_000)
    }

    @Test("the settings' own values give the same clamped policy as the stored ones (Activity's caption reads them)")
    func whenChosenFromSettingsValues_thenSameAsFromDefaults() {
        #expect(RetentionPolicy.chosen(days: 0, maxItems: 50).maxAge == .infinity)
        #expect(RetentionPolicy.chosen(days: 0, maxItems: 50).maxItemCount == 100)
        #expect(RetentionPolicy.chosen(days: 7, maxItems: 1000).maxAge == 7 * 24 * 60 * 60)
        #expect(RetentionPolicy.chosen(days: nil, maxItems: nil) == .default)
    }
}
