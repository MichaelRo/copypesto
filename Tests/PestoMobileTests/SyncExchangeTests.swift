// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

@MainActor
private final class RecordingSync: SyncExchanging {
    var isEnabled: Bool
    private(set) var calls: [String] = []

    init(enabled: Bool) {
        isEnabled = enabled
    }

    func activate() {
        calls.append("activate")
    }

    func syncNow() async {
        calls.append("syncNow")
    }

    func deactivate() {
        calls.append("deactivate")
    }
}

@Suite("Sync runs without a button: on pull to refresh and in a background refresh")
@MainActor
struct SyncExchangeTests {
    @Test("pull to refresh exchanges only when sync is on, on the open folder")
    func whenPulled_thenItExchangesOnlyWithSyncOn() async {
        let on = RecordingSync(enabled: true)
        let off = RecordingSync(enabled: false)
        await SyncExchange.onPull(on)
        await SyncExchange.onPull(off)
        await SyncExchange.onPull(nil)
        #expect(on.calls == ["syncNow"])
        #expect(off.calls.isEmpty)
    }

    @Test("the background refresh opens the folder, runs the same exchange once and lets the folder go")
    func whenRefreshedInTheBackground_thenOneExchangeBetweenOpenAndClose() async {
        let on = RecordingSync(enabled: true)
        #expect(await SyncExchange.inBackground(on))
        #expect(on.calls == ["activate", "syncNow", "deactivate"])

        let off = RecordingSync(enabled: false)
        #expect(await SyncExchange.inBackground(off) == false)
        #expect(off.calls == ["activate", "deactivate"])
    }

    @Test("a refresh is asked for only with sync on, a history and a normal launch")
    func whenDecidingToSchedule_thenEveryConditionCounts() {
        #expect(BackgroundSyncPolicy.shouldSchedule(syncEnabled: true, historyAvailable: true, mode: .normal))
        #expect(!BackgroundSyncPolicy.shouldSchedule(syncEnabled: false, historyAvailable: true, mode: .normal))
        #expect(!BackgroundSyncPolicy.shouldSchedule(syncEnabled: true, historyAvailable: false, mode: .normal))
        #expect(!BackgroundSyncPolicy.shouldSchedule(syncEnabled: true, historyAvailable: true, mode: .uiTest))
        #expect(!BackgroundSyncPolicy.shouldSchedule(syncEnabled: true, historyAvailable: true, mode: .hostedTests))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(BackgroundSyncPolicy.earliestBegin(after: now) > now)
    }

    @Test("the app declares the task it schedules, and may fetch in the background")
    func whenTheAppIsBuilt_thenItsInfoListsTheTask() {
        let info = Bundle.main.infoDictionary ?? [:]
        let identifiers = info["BGTaskSchedulerPermittedIdentifiers"] as? [String] ?? []
        #expect(identifiers == [AppIdentity.syncRefreshTaskID])
        #expect((info["UIBackgroundModes"] as? [String])?.contains("fetch") == true)
    }
}
