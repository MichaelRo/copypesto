// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("The Mac's Keep history for policy sweeps the iPhone and iPad history")
@MainActor
struct MobileRetentionTests {
    private let policy = RetentionPolicy.chosen(days: 30, maxItems: 5000)

    @Test("a sweep after the age limit removes unpinned clips and keeps pinned ones")
    func whenSweptAfterTheAgeLimit_thenOnlyPinnedClipsStay() async throws {
        let time = TimeBox()
        let library = try await MobileTestLibrary(clock: { time.now })
        library.state.retentionPolicy = { RetentionPolicy.chosen(days: 30, maxItems: 5000) }
        let old = try await library.add("an old clip")
        let kept = try await library.add("a pinned clip")
        _ = try await library.service.togglePinned(id: kept.id)
        try await library.refreshed()

        time.advance(by: 40 * 86_400)
        await library.state.sweepRetention(force: true)
        try await library.refreshed()

        #expect(library.store.item(for: old.id) == nil)
        #expect(library.store.item(for: kept.id) != nil)
    }

    @Test("forever keeps everything")
    func whenKeepingForever_thenNothingIsRemoved() async throws {
        let time = TimeBox()
        let library = try await MobileTestLibrary(clock: { time.now })
        library.state.retentionPolicy = { RetentionPolicy.chosen(days: RetentionChoices.foreverDays, maxItems: 5000) }
        let old = try await library.add("an old clip")

        time.advance(by: 400 * 86_400)
        await library.state.sweepRetention(force: true)
        try await library.refreshed()

        #expect(library.store.item(for: old.id) != nil)
    }

    @Test("a sweep runs at launch, then at most once an hour on coming back, and at once when the policy changes")
    func whenScheduled_thenTheTriggersAreDecided() {
        var schedule = RetentionSchedule()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(schedule.shouldSweep(now: start, policy: policy, force: false))

        schedule.didSweep(at: start, policy: policy)
        #expect(!schedule.shouldSweep(now: start.addingTimeInterval(600), policy: policy, force: false))
        #expect(schedule.shouldSweep(now: start.addingTimeInterval(600), policy: policy, force: true))
        #expect(schedule.shouldSweep(now: start.addingTimeInterval(3601), policy: policy, force: false))
        let shorter = RetentionPolicy.chosen(days: 7, maxItems: 5000)
        #expect(schedule.shouldSweep(now: start.addingTimeInterval(60), policy: shorter, force: false))
    }

    @Test("coming back to the foreground twice in a row sweeps once")
    func whenForegroundedTwice_thenOneSweep() async throws {
        let time = TimeBox()
        let library = try await MobileTestLibrary(clock: { time.now })
        library.state.retentionPolicy = { RetentionPolicy.chosen(days: 30, maxItems: 5000) }
        await library.state.sweepRetention()
        let first = library.state.retentionSchedule.lastSweep
        time.advance(by: 60)
        await library.state.sweepRetention()

        #expect(first != nil)
        #expect(library.state.retentionSchedule.lastSweep == first)
    }

    @Test("the choices and the default are the Mac's")
    func whenChoices_thenTheMacs() {
        #expect(Setting.retentionDays.defaultValue == 30)
        #expect(Setting.retentionMaxItems.defaultValue == 5000)
        #expect(RetentionChoices.ageLabel(30) == "1 month")
        #expect(RetentionChoices.ageLabel(RetentionChoices.foreverDays) == "Forever")
    }
}
