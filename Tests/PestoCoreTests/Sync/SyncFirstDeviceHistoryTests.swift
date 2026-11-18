// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The device that turns sync on first sends the history it had before", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct SyncFirstDeviceHistoryTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pesto-first-\(UUID().uuidString)")
    let time = TimeBox()

    @Test("clips copied before sync was on reach a device that joins the sync the first device made")
    func whenTheFirstDeviceHadHistory_thenItIsWrittenToTheFolder() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try SyncMac(name: "mac-a", folder: folder, time: time)
        SyncJournal.disable(for: first.container)
        try await first.site.copy("copied before sync was on")
        await first.controller.turnOn()
        guard case let .recoveryKey(key) = first.controller.flow else {
            Issue.record("expected the recovery key, got \(first.controller.flow)")
            return
        }
        time.advance()
        await first.controller.syncNow()

        let second = try SyncMac(name: "mac-b", folder: folder, time: time)
        await second.controller.turnOn()
        await second.controller.useRecoveryKey(key)
        second.controller.confirmJoin()
        for _ in 0..<2 {
            for mac in [first, second] {
                time.advance()
                await mac.controller.syncNow()
            }
        }

        #expect(try second.clips() == ["copied before sync was on"], "\(second.controller.status)")
    }

    /// A Mac that made its group before the history was stamped at turn-on is already announced, so no later pass sent
    /// what it held. The next launch sends every clip and collection that still carries no stamp.
    @Test("a first device that never sent its older history sends it after its next launch")
    func whenAnAnnouncedDeviceHoldsUnstampedClips_thenTheNextLaunchSendsThem() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try SyncMac(name: "mac-a", folder: folder, time: time)
        await first.controller.turnOn()
        guard case let .recoveryKey(key) = first.controller.flow else {
            Issue.record("expected the recovery key, got \(first.controller.flow)")
            return
        }
        time.advance()
        await first.controller.syncNow()
        SyncJournal.disable(for: first.container)
        try await first.site.copy("left behind by the old turn-on")

        let second = try SyncMac(name: "mac-b", folder: folder, time: time)
        await second.controller.turnOn()
        await second.controller.useRecoveryKey(key)
        second.controller.confirmJoin()
        let relaunched = first.relaunched()
        relaunched.resumeIfEnabled()
        for _ in 0..<2 {
            for controller in [relaunched, second.controller] {
                time.advance()
                await controller.syncNow()
            }
        }

        #expect(try second.clips() == ["left behind by the old turn-on"], "\(second.controller.status)")
    }
}
