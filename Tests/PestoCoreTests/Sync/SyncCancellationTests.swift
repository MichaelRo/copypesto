// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@MainActor
private final class StopOnFirstPass {
    weak var service: SyncFolderService?
    private(set) var stops = 0

    func stopOnce() -> Bool {
        if stops == 0 {
            stops += 1
            service?.stop()
        }
        return false
    }
}

@Suite("A sync pass stops when sync is stopped under it", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct SyncCancellationTests {
    let layout = SyncFolderLayout(
        root: FileManager.default.temporaryDirectory.appendingPathComponent("pesto-sync-cancel-\(UUID().uuidString)")
    )
    let time = TimeBox()

    @Test("records applied in a cancelled task stop at the first one, apply nothing and say so")
    func whenTheTaskIsCancelled_thenApplyStopsAndThrows() async throws {
        let world = try SyncWorld(["mac-a", "mac-b"])
        let (macA, macB) = (world.macs[0], world.macs[1])
        for index in 0..<5 {
            try await world.copy("record \(index)", on: macA)
        }
        let records = try await world.publish(from: macA)
        let service = macB.service

        let task = Task {
            try? await Task.sleep(for: .seconds(30))
            return try await service.applySync(records)
        }
        task.cancel()
        let result = await task.result

        #expect(throws: CancellationError.self) { try result.get() }
        #expect(try world.clips(on: macB).isEmpty)
    }

    @Test("stopping the service while its pass runs ends the pass: nothing is read, and a later pass reads it all")
    func whenStoppedDuringAPass_thenThePassEndsWithoutReading() async throws {
        defer { try? FileManager.default.removeItem(at: layout.root) }
        let a = try SyncSite(name: "mac-a", layout: layout, time: time)
        let b = try SyncSite(name: "mac-b", layout: layout, time: time)
        let made = try SyncGroupManager.create(
            layout: layout,
            identity: a.identity,
            keyStore: a.keyStore,
            now: time.now
        )
        try b.keyStore.saveSyncKey(made.group.key, vaultID: made.group.vault.vaultID, epoch: 1)
        for text in ["one", "two", "three"] {
            try await a.copy(text)
        }
        time.advance()
        await a.service.syncNow()

        let trap = StopOnFirstPass()
        let stopping = SyncFolderService(
            container: b.container, storage: b.storage, layout: layout, identity: b.identity, keyStore: b.keyStore,
            highWater: b.highWater, isLocked: { trap.stopOnce() }, now: { self.time.now }
        )
        trap.service = stopping
        time.advance()
        let status = await stopping.syncNow()

        #expect(trap.stops == 1)
        #expect(status == .off)
        #expect(try b.texts().isEmpty)
        #expect(b.highWater.load().mark(for: "mac-a") == nil)

        time.advance()
        await b.service.syncNow()
        #expect(try b.texts() == ["one", "three", "two"])
    }
}
