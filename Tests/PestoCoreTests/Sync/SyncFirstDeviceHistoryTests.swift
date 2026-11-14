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
}
