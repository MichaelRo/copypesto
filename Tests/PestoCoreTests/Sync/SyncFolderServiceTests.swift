// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

final class MemoryHighWater: SyncHighWaterStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var water = SyncHighWater()
    func load() -> SyncHighWater {
        lock.withLock { water }
    }

    func save(_ new: SyncHighWater) {
        lock.withLock { water = new }
    }
}

/// One simulated Mac: its own store, clock, keys and sync service, working in a shared folder.
@MainActor
final class SyncSite {
    let name: String
    let container: ModelContainer
    let storage: StorageService
    let identity: SyncIdentity
    let secrets = MemorySecrets()
    let keyStore: ThisDeviceSyncKeyStore
    let service: SyncFolderService
    var locked = false

    init(name: String, layout: SyncFolderLayout, time: TimeBox) throws {
        self.name = name
        container = try ModelContainerSetup.makeInMemory().synced
        storage = StorageService(modelContainer: container)
        identity = SyncIdentity(deviceID: name, name: name, keys: .generate())
        keyStore = ThisDeviceSyncKeyStore(secrets: secrets)
        SyncJournal.enable(
            for: container,
            clock: SyncClock(deviceID: name, defaults: ThrowawayDefaults.make(), now: { time.now })
        )
        var timing = SyncFolderService.Timing()
        timing.batchWindow = .milliseconds(50)
        let flag = LockedFlag()
        service = SyncFolderService(
            container: container, storage: storage, layout: layout, identity: identity, keyStore: keyStore,
            highWater: MemoryHighWater(), timing: timing, includeSensitive: { false }, isLocked: { flag.value },
            now: { time.now }
        )
        lockedFlag = flag
    }

    var lockedFlag = LockedFlag()
    deinit { SyncJournal.disable(for: container) }

    func copy(_ text: String) async throws {
        let payload = Data(text.utf8)
        try await storage.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: payload, payloadString: text,
            frontmostBundleID: "com.apple.Notes", timestamp: .now,
            contentHash: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        ))
    }

    func texts() throws -> [String] {
        try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).compactMap { $0.blob?.decryptedText() }
            .sorted()
    }

    func item(_ text: String) throws -> ClipboardItem? {
        try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first { $0.blob?.decryptedText() == text }
    }
}

final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool {
        get { lock.withLock { flag } }
        set { lock.withLock { flag = newValue } }
    }
}

@Suite("Sync folder service: two Macs through a folder", .serialized)
@MainActor
struct SyncFolderServiceTests {
    let layout = SyncFolderLayout(
        root: FileManager.default.temporaryDirectory.appendingPathComponent("pesto-sync-folder-\(UUID().uuidString)")
    )
    let time = TimeBox()

    /// A first Mac that made the group, and a second that holds its key.
    private func pair() throws -> (a: SyncSite, b: SyncSite) {
        let a = try SyncSite(name: "mac-a", layout: layout, time: time)
        let b = try SyncSite(name: "mac-b", layout: layout, time: time)
        let made = try SyncGroupManager.create(
            layout: layout,
            identity: a.identity,
            keyStore: a.keyStore,
            now: time.now
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

    @Test("a clip copied on one Mac arrives on the other, and an edit and a deletion follow")
    func roundTrip() async throws {
        let (a, b) = try pair()
        try await a.copy("hello")
        await settle(a, b)
        #expect(try b.texts() == ["hello"])
        guard case .upToDate = b.service.status else {
            Issue.record("B status is \(b.service.status)")
            return
        }

        let context = ModelContext(a.container)
        try #require(context.fetch(FetchDescriptor<ClipboardItem>()).first).customTitle = "Greeting"
        try context.saveOrRollback()
        await settle(a, b)
        #expect(try b.item("hello")?.customTitle == "Greeting")

        let id = try #require(b.item("hello")?.id)
        try await b.storage.deleteItems(ids: [id], reason: .user)
        await settle(b, a)
        #expect(try a.texts().isEmpty)
    }

    @Test("a history that existed before sync is written when the Mac joins, and a restart writes nothing again")
    func firstSync() async throws {
        let (a, b) = try pair()
        for text in ["one", "two", "three"] {
            try await a.copy(text)
        }
        await settle(a, b)
        #expect(try b.texts() == ["one", "three", "two"])

        let before = try FileManager.default.contentsOfDirectory(atPath: layout.log("mac-a").path).count
        let restarted = SyncFolderService(
            container: a.container, storage: a.storage, layout: layout, identity: a.identity, keyStore: a.keyStore,
            highWater: MemoryHighWater(), timing: .init(), now: { self.time.now }
        )
        await restarted.syncNow()
        #expect(try FileManager.default.contentsOfDirectory(atPath: layout.log("mac-a").path).count == before)
    }

    @Test("a payload over the inline limit travels as a sealed file beside the log")
    func bigPayload() async throws {
        let (a, b) = try pair()
        let big = String(repeating: "pesto ", count: 60_000)
        try await a.copy(big)
        let judging = ModelContext(a.container)
        try judging.fetch(FetchDescriptor<ClipboardItem>()).forEach { $0.analysisPending = false }
        try judging.saveOrRollback()
        await settle(a, b)
        #expect(try FileManager.default.contentsOfDirectory(atPath: layout.blobs("mac-a").path).count == 1)
        #expect(try b.texts() == [big])
    }

    @Test("a segment that was changed is refused, nothing is applied, and the Mac says so")
    func tamperedSegment() async throws {
        let (a, b) = try pair()
        try await a.copy("secret plans")
        time.advance()
        await a.service.syncNow()
        let file = try #require(
            FileManager.default.contentsOfDirectory(atPath: layout.log("mac-a").path)
                .first { $0.hasSuffix(".pestolog") }
        )
        let url = layout.log("mac-a").appendingPathComponent(file)
        var data = try Data(contentsOf: url)
        data[data.count / 2] ^= 1
        try data.write(to: url)

        await b.service.syncNow()

        #expect(try b.texts().isEmpty)
        guard case .refused = b.service.status else {
            Issue.record("B status is \(b.service.status)")
            return
        }
    }

    @Test("a missing earlier segment makes the Mac wait instead of applying a later one")
    func gap() async throws {
        let (a, b) = try pair()
        try await a.copy("first")
        await settle(a, b)
        try await a.copy("second")
        await settle(a)
        let names = try FileManager.default.contentsOfDirectory(atPath: layout.log("mac-a").path)
            .filter { $0.hasSuffix(".pestolog") }.sorted()
        try await a.copy("third")
        await settle(a)
        let all = try FileManager.default.contentsOfDirectory(atPath: layout.log("mac-a").path)
            .filter { $0.hasSuffix(".pestolog") }.sorted()
        #expect(all.count > names.count)
        try FileManager.default.removeItem(at: layout.log("mac-a").appendingPathComponent(names.last ?? ""))

        await settle(b)
        #expect(try b.texts() == ["first"], "the later segment waits for the one before it")
        #expect(b.service.status == .waitingForFolder)
    }

    @Test("a locked history pauses sync both ways, and a missing folder, an empty one and a missing key are named")
    func states() async throws {
        let (a, _) = try pair()
        try await a.copy("kept here")
        a.lockedFlag.value = true
        await a.service.syncNow()
        #expect(a.service.status == .paused)
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: layout.log("mac-a").path)) ?? []).isEmpty)

        let nowhere = SyncFolderLayout(root: layout.root.appendingPathComponent("not-here"))
        let lost = try SyncSite(name: "mac-x", layout: nowhere, time: time)
        await lost.service.syncNow()
        #expect(lost.service.status == .folderMissing)

        let emptyLayout = SyncFolderLayout(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-empty-\(UUID().uuidString)"))
        try FileManager.default.createDirectory(at: emptyLayout.root, withIntermediateDirectories: true)
        let fresh = try SyncSite(name: "mac-y", layout: emptyLayout, time: time)
        await fresh.service.syncNow()
        #expect(fresh.service.status == .waitingForFolder)

        let keyless = try SyncSite(name: "mac-z", layout: layout, time: time)
        await keyless.service.syncNow()
        #expect(keyless.service.status == .needsKey)
    }

    @Test("Reset Sync: the other Mac switches to the new key and writes its history again, and new clips flow")
    func resetSync() async throws {
        let (a, b) = try pair()
        try await a.copy("before the reset")
        await settle(a, b)
        #expect(try b.texts() == ["before the reset"])

        guard case let .ready(group) = try SyncGroupManager.open(layout: layout, keyStore: a.keyStore) else {
            Issue.record("no group")
            return
        }
        let next = try SyncGroupManager.reset(
            layout: layout, from: group, identity: a.identity, keyStore: a.keyStore, now: time.now
        )
        try b.keyStore.saveSyncKey(next.group.key, vaultID: next.group.vault.vaultID, epoch: 2)

        try await b.copy("after the reset")
        await settle(a, b, a)
        #expect(try a.texts() == ["after the reset", "before the reset"])
        #expect(try b.texts() == ["after the reset", "before the reset"])
    }

    @Test("the folder watcher reports a file that appears in the folder")
    func watcher() async throws {
        try FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
        let seen = LockedFlag()
        let watcher = SyncFolderWatcher(url: layout.root, latency: 0.1) { seen.value = true }
        watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(300))
        try Data("x".utf8).write(to: layout.root.appendingPathComponent("probe.txt"))
        for _ in 0..<40 where !seen.value {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(seen.value)
    }
}
