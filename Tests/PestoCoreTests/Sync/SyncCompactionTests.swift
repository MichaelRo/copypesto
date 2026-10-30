// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

struct SyncPair {
    let a: SyncSite
    let b: SyncSite
    let group: SyncGroup
}

@Suite("Sync compaction: a long log becomes a snapshot and the old files go", .serialized)
@MainActor
struct SyncCompactionTests {
    let layout = SyncFolderLayout(
        root: FileManager.default.temporaryDirectory.appendingPathComponent("pesto-sync-compact-\(UUID().uuidString)")
    )
    let time = TimeBox()

    private func sites() throws -> SyncPair {
        var timing = SyncFolderService.Timing()
        timing.compactAfterSegments = 4
        let a = try SyncSite(name: "mac-a", layout: layout, time: time, timing: timing)
        let b = try SyncSite(name: "mac-b", layout: layout, time: time)
        let made = try SyncGroupManager.create(
            layout: layout, identity: a.identity, keyStore: a.keyStore, now: time.now
        )
        try b.keyStore.saveSyncKey(made.group.key, vaultID: made.group.vault.vaultID, epoch: 1)
        return SyncPair(a: a, b: b, group: made.group)
    }

    private func segments(_ device: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: layout.log(device).path)
            .filter { $0.hasSuffix(".pestolog") }.sorted()
    }

    private func copyMany(_ site: SyncSite, _ prefix: String, count: Int) async throws {
        for index in 0..<count {
            try await site.copy("\(prefix) \(index)")
            time.advance()
            await site.service.syncNow()
        }
    }

    @Test("past the limit the old segments are replaced by a snapshot, and a Mac that joins later gets everything")
    func lateJoiner() async throws {
        let pair = try sites()
        let a = pair.a, group = pair.group
        try await copyMany(a, "clip", count: 10)
        let remaining = try segments("mac-a")
        #expect(remaining.count < 10, "compaction did not run: \(remaining)")

        let c = try SyncSite(name: "mac-c", layout: layout, time: time)
        try c.keyStore.saveSyncKey(group.key, vaultID: group.vault.vaultID, epoch: 1)
        await c.service.syncNow()
        #expect(try c.texts() == (0..<10).map { "clip \($0)" }.sorted())
    }

    @Test("a Mac that was behind jumps to the snapshot and ends alike; later changes still flow")
    func laggard() async throws {
        let pair = try sites()
        let a = pair.a, b = pair.b
        try await a.copy("early")
        time.advance()
        await a.service.syncNow()
        await b.service.syncNow()
        try await copyMany(a, "later", count: 10)
        #expect(try segments("mac-a").first.map { SyncFolderService.sequenceRange(of: $0)?.first ?? 0 } != 1)

        await b.service.syncNow()
        #expect(try b.texts() == (["early"] + (0..<10).map { "later \($0)" }).sorted())
        try await a.copy("after")
        time.advance()
        await a.service.syncNow()
        await b.service.syncNow()
        #expect(try b.texts().contains("after"))
    }

    @Test("a deletion made before compaction is not undone for a Mac that joins afterwards")
    func deletionSurvives() async throws {
        let pair = try sites()
        let a = pair.a, group = pair.group
        try await a.copy("to delete")
        time.advance()
        await a.service.syncNow()
        let doomed = try #require(try a.item("to delete"))
        _ = try await a.storage.deleteItem(id: doomed.id)
        time.advance()
        await a.service.syncNow()
        try await copyMany(a, "keep", count: 8)

        let c = try SyncSite(name: "mac-c", layout: layout, time: time)
        try c.keyStore.saveSyncKey(group.key, vaultID: group.vault.vaultID, epoch: 1)
        await c.service.syncNow()
        #expect(try !c.texts().contains("to delete"))
        #expect(try c.texts().count == 8)
    }

    @Test("compaction keeps the log small however long it runs")
    func staysSmall() async throws {
        let a = try sites().a
        try await copyMany(a, "n", count: 30)
        #expect(try segments("mac-a").count <= 8)
    }

    @Test("a clip received from another Mac is not copied into this Mac's snapshot")
    func othersAreNotCopied() async throws {
        let pair = try sites()
        let a = pair.a, b = pair.b
        try await b.copy("from b")
        time.advance()
        await b.service.syncNow()
        await a.service.syncNow()
        try await copyMany(a, "mine", count: 8)

        let ownRecords = try segments("mac-a").flatMap { name -> [SyncRecord] in
            guard case let .ready(group) = try SyncGroupManager.open(layout: layout, keyStore: a.keyStore) else {
                return []
            }
            let data = try Data(contentsOf: layout.log("mac-a").appendingPathComponent(name))
            let verified = try SyncSegmentReader.verify(
                data, syncKey: group.key, trust: group.trust, vaultID: group.vault.vaultID, epoch: group.epoch
            )
            return try verified.records()
        }
        let fromB = ownRecords.filter { record in
            (try? record.decodeMetadata(SyncItemRecord.self).plainHash).map { _ in record.stamp.deviceID == "mac-b" }
                ?? false
        }
        #expect(fromB.isEmpty)
    }
}
