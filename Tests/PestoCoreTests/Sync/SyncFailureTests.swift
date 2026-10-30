// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite(
    "Sync folder service: files that are late, half written, damaged or from a wrong clock",
    .serialized,
    .timeLimit(.minutes(1))
)
@MainActor
struct SyncFailureTests {
    let layout = SyncFolderLayout(
        root: FileManager.default.temporaryDirectory.appendingPathComponent("pesto-sync-failure-\(UUID().uuidString)")
    )
    let time = TimeBox()

    private func pair(bTime: TimeBox? = nil) throws -> (a: SyncSite, b: SyncSite) {
        let a = try SyncSite(name: "mac-a", layout: layout, time: time)
        let b = try SyncSite(name: "mac-b", layout: layout, time: bTime ?? time)
        let made = try SyncGroupManager.create(
            layout: layout, identity: a.identity, keyStore: a.keyStore, now: time.now
        )
        try b.keyStore.saveSyncKey(made.group.key, vaultID: made.group.vault.vaultID, epoch: 1)
        return (a, b)
    }

    private func settle(_ sites: SyncSite...) async {
        for _ in 0..<2 {
            for site in sites {
                time.advance()
                await site.service.syncNow()
            }
        }
    }

    private func logFile(_ device: String) throws -> URL {
        let name = try #require(
            FileManager.default.contentsOfDirectory(atPath: layout.log(device).path)
                .filter { $0.hasSuffix(".pestolog") }.min()
        )
        return layout.log(device).appendingPathComponent(name)
    }

    @Test("a half-written segment applies nothing, and the whole file applies when it arrives")
    func halfWritten() async throws {
        let (a, b) = try pair()
        try await a.copy("arrives whole")
        time.advance()
        await a.service.syncNow()
        let url = try logFile("mac-a")
        let whole = try Data(contentsOf: url)
        try whole.prefix(whole.count / 2).write(to: url)

        await b.service.syncNow()
        #expect(try b.texts().isEmpty)

        try whole.write(to: url)
        time.advance()
        await b.service.syncNow()
        #expect(try b.texts() == ["arrives whole"])
    }

    @Test("a refused segment is not forever: the original file brings the clip in")
    func refusalHeals() async throws {
        let (a, b) = try pair()
        try await a.copy("restored by the original")
        time.advance()
        await a.service.syncNow()
        let url = try logFile("mac-a")
        let original = try Data(contentsOf: url)
        var damaged = original
        damaged[damaged.count / 2] ^= 1
        try damaged.write(to: url)
        await b.service.syncNow()
        #expect(try b.texts().isEmpty)

        try original.write(to: url)
        time.advance()
        await b.service.syncNow()
        #expect(try b.texts() == ["restored by the original"])
    }

    @Test("unfinished uploads and files Pesto does not own are ignored")
    func strangers() async throws {
        let (a, b) = try pair()
        try await a.copy("real")
        time.advance()
        await a.service.syncNow()
        let folder = layout.log("mac-a")
        try Data("x".utf8).write(to: folder.appendingPathComponent("0000000000000099.pestolog.partial"))
        try Data("x".utf8).write(to: folder.appendingPathComponent(".DS_Store"))
        try Data("x".utf8).write(to: folder.appendingPathComponent("notes.txt"))
        try Data("x".utf8).write(to: layout.root.appendingPathComponent("Icon\r"))

        await b.service.syncNow()

        #expect(try b.texts() == ["real"])
        guard case .upToDate = b.service.status else {
            Issue.record("B status is \(b.service.status)")
            return
        }
    }

    @Test("the folder goes away and comes back: the Mac says so, then catches up")
    func folderVanishes() async throws {
        let (a, b) = try pair()
        try await a.copy("before")
        await a.service.syncNow()
        let moved = layout.root.deletingLastPathComponent().appendingPathComponent("moved-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: layout.root, to: moved)

        await b.service.syncNow()
        #expect(b.service.status == .folderMissing)
        try FileManager.default.moveItem(at: moved, to: layout.root)
        time.advance()
        await b.service.syncNow()
        #expect(try b.texts() == ["before"])
    }

    @Test("a Mac whose clock is a month ahead is refused, and nothing it wrote is applied")
    func clockFarAhead() async throws {
        let ahead = TimeBox()
        ahead.advance(by: 30 * 86_400)
        let a = try SyncSite(name: "mac-a", layout: layout, time: ahead)
        let b = try SyncSite(name: "mac-b", layout: layout, time: time)
        let made = try SyncGroupManager.create(
            layout: layout, identity: a.identity, keyStore: a.keyStore, now: ahead.now
        )
        try b.keyStore.saveSyncKey(made.group.key, vaultID: made.group.vault.vaultID, epoch: 1)
        try await a.copy("from the future")
        ahead.advance()
        await a.service.syncNow()

        await b.service.syncNow()

        #expect(try b.texts().isEmpty)
        guard case .refused = b.service.status else {
            Issue.record("B status is \(b.service.status)")
            return
        }

        time.advance(by: 30 * 86_400)
        await b.service.syncNow()
        #expect(try b.texts() == ["from the future"], "the refused file is read again once the clocks agree")
    }

    @Test("a clock that runs backwards on one Mac does not lose a later edit")
    func clockBackwards() async throws {
        let (a, b) = try pair()
        try await a.copy("first")
        await a.service.syncNow()
        await b.service.syncNow()
        time.advance(by: -3600)
        try await a.copy("second, after the clock moved back")
        await a.service.syncNow()
        await b.service.syncNow()
        #expect(try b.texts() == ["first", "second, after the clock moved back"])
    }

    @Test("one Mac's damaged file is reported, and the other Macs' clips still arrive")
    func oneBadDeviceDoesNotBlockTheOthers() async throws {
        let (a, b) = try pair()
        let c = try SyncSite(name: "mac-c", layout: layout, time: time)
        guard case let .ready(group) = try SyncGroupManager.open(layout: layout, keyStore: a.keyStore) else {
            Issue.record("no group")
            return
        }
        try c.keyStore.saveSyncKey(group.key, vaultID: group.vault.vaultID, epoch: 1)
        try await a.copy("from the damaged Mac")
        await settle(a, b)
        try await c.copy("from the healthy Mac")
        await settle(c, a, b)
        try await a.copy("a second clip so there is a second file")
        time.advance()
        await a.service.syncNow()
        let files = try FileManager.default.contentsOfDirectory(atPath: layout.log("mac-a").path)
            .filter { $0.hasSuffix(".pestolog") }.sorted()
        let newest = try layout.log("mac-a").appendingPathComponent(#require(files.last))
        var data = try Data(contentsOf: newest)
        data[data.count / 2] ^= 1
        try data.write(to: newest)
        try await c.copy("written after the damage")

        await settle(c)
        await b.service.syncNow()

        #expect(try b.texts().contains("written after the damage"), "a damaged file from A blocked C's clips")
        guard case .refused = b.service.status else {
            Issue.record("B should still say what is wrong, got \(b.service.status)")
            return
        }
    }

    @Test("a damaged last segment of this Mac's own log stops writing instead of chaining from a zero hash")
    func damagedOwnLogDoesNotBreakTheChain() async throws {
        let (a, _) = try pair()
        try await a.copy("one")
        time.advance()
        await a.service.syncNow()
        let url = try logFile("mac-a")
        let before = try FileManager.default.contentsOfDirectory(atPath: layout.log("mac-a").path).count
        try Data(Data(contentsOf: url).prefix(40)).write(to: url)
        try await a.copy("two")
        let restarted = SyncFolderService(
            container: a.container, storage: a.storage, layout: layout, identity: a.identity, keyStore: a.keyStore,
            highWater: MemoryHighWater(), now: { time.now }
        )

        time.advance()
        await restarted.syncNow()

        let after = try FileManager.default.contentsOfDirectory(atPath: layout.log("mac-a").path).count
        #expect(after == before, "a segment was written after a damaged one, with no way to chain it")
        guard case .refused = restarted.status else {
            Issue.record("expected a refusal, got \(restarted.status)")
            return
        }
    }
}
