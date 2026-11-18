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
        await library.state.pruneHistory(force: true)
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
        await library.state.pruneHistory(force: true)
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
        await library.state.pruneHistory()
        let first = library.state.retentionSchedule.lastSweep
        time.advance(by: 60)
        await library.state.pruneHistory()

        #expect(first != nil)
        #expect(library.state.retentionSchedule.lastSweep == first)
    }

    @Test("lowering the limit counts the clips it would delete, not the ones the current limit already takes")
    func whenLowered_thenTheCountIsWhatTheChangeDeletes() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day = 86_400.0
        let candidates = [(UUID(), now.addingTimeInterval(-200 * day), 10), (UUID(), now.addingTimeInterval(-60 * day), 10),
                          (UUID(), now.addingTimeInterval(-10 * day), 10), (UUID(), now.addingTimeInterval(-1 * day), 10)]
        let snapshot = RetentionSnapshot(candidates: candidates, expired: [])
        let year = RetentionPolicy.chosen(days: 365, maxItems: 5000)

        #expect(RetentionPreview.clipsLeaving(
            snapshot: snapshot, current: year, proposed: .chosen(days: 30, maxItems: 5000), now: now
        ) == 2)
        #expect(RetentionPreview.clipsLeaving(
            snapshot: snapshot, current: .chosen(days: 30, maxItems: 5000), proposed: .chosen(days: 7, maxItems: 5000),
            now: now
        ) == 1)
        #expect(RetentionPreview.clipsLeaving(
            snapshot: snapshot, current: year, proposed: .chosen(days: 365, maxItems: 5000), now: now
        ) == 0)
    }

    @Test("the app state counts what a shorter age limit would delete from the real history")
    func whenTheAgeIsShortened_thenTheHistoryIsCounted() async throws {
        let time = TimeBox()
        let library = try await MobileTestLibrary(clock: { time.now })
        library.state.retentionPolicy = { RetentionPolicy.chosen(days: 365, maxItems: 5000) }
        try await library.add("old one")
        try await library.add("old two")
        time.advance(by: 40 * 86_400)

        let shorter = await library.state.clipsLeaving(days: 30, maxItems: 5000)
        let longer = await library.state.clipsLeaving(days: 365, maxItems: 5000)
        #expect(shorter == 2)
        #expect(longer == 0)
    }

    @Test("the choices and the default are the Mac's")
    func whenChoices_thenTheMacs() {
        #expect(Setting.retentionDays.defaultValue == 30)
        #expect(Setting.retentionMaxItems.defaultValue == 5000)
        #expect(RetentionChoices.ageLabel(30) == "1 month")
        #expect(RetentionChoices.ageLabel(RetentionChoices.foreverDays) == "Forever")
    }
}
