// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("Sync journal: what is stamped, what is held back, what a deletion remembers", .serialized)
struct SyncJournalTests {
    let container: ModelContainer
    let service: StorageService
    let defaults = ThrowawayDefaults.make()

    init() throws {
        container = try ModelContainerSetup.makeInMemory().synced
        service = StorageService(modelContainer: container)
    }

    private func enable(deviceID: String = "mac-a") {
        SyncJournal.enable(for: container, clock: SyncClock(deviceID: deviceID, defaults: defaults))
    }

    private func ingest(_ text: String) async throws {
        let payload = Data(text.utf8)
        try await service.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: payload, payloadString: text,
            frontmostBundleID: "com.apple.Notes", timestamp: .now,
            contentHash: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        ))
    }

    private func items() throws -> [ClipboardItem] {
        try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp)]))
    }

    private func item(_ text: String) throws -> ClipboardItem {
        try #require(items().first { $0.displayPreviewText == text })
    }

    // MARK: Stamping

    @Test("with sync off nothing is stamped")
    func whenOff_thenNothingIsStamped() async throws {
        try await ingest("plain")
        let clip = try item("plain")
        #expect(clip.changeClock == nil && clip.syncFingerprint == nil && clip.syncDirty == nil)
    }

    @Test("with sync on a new clip is stamped, dirty, and later clips are stamped later")
    func whenOn_thenNewClipsAreStampedInOrder() async throws {
        enable()
        defer { SyncJournal.disable(for: container) }
        try await ingest("first")
        try await ingest("second")

        let first = try item("first"), second = try item("second")
        let firstStamp = try #require(first.changeClock.flatMap(SyncStamp.init(encoded:)))
        let secondStamp = try #require(second.changeClock.flatMap(SyncStamp.init(encoded:)))
        #expect(firstStamp < secondStamp && firstStamp.deviceID == "mac-a")
        #expect(first.syncDirty == true && first.syncFingerprint != nil && first.syncEmittedClock == nil)
    }

    @Test("a change to a synced field stamps again; a write to something only this Mac cares about does not")
    func whenOnlyThisMacsFieldsChange_thenNoNewStamp() async throws {
        enable()
        defer { SyncJournal.disable(for: container) }
        try await ingest("edit me")
        let id = try item("edit me").id
        let before = try #require(item("edit me").changeClock)

        _ = try await service.notePasted(id: id)
        #expect(try item("edit me").changeClock == before, "a paste only counts; it is not a synced change")

        _ = try await service.togglePinned(id: id)
        let after = try #require(item("edit me").changeClock)
        #expect(try after > before && item("edit me").isPinned)
    }

    @Test("what another Mac said keeps its own stamp: a save applying a remote change stamps nothing")
    func whenApplyingRemote_thenNothingIsStamped() async throws {
        enable()
        defer { SyncJournal.disable(for: container) }
        try await SyncJournal.$isApplyingRemote.withValue(true) { try await ingest("from afar") }
        let clip = try item("from afar")
        #expect(clip.changeClock == nil && clip.syncDirty == nil)
    }

    @Test("a collection is stamped when it is made and when it changes")
    func collections() throws {
        enable()
        defer { SyncJournal.disable(for: container) }
        let context = ModelContext(container)
        let board = Pinboard(name: "Ship", symbolName: "shippingbox", colorHex: "#2F7A49", sortOrder: 0)
        context.insert(board)
        try context.saveOrRollback()
        let created = try #require(board.changeClock)
        board.name = "Shipping"
        try context.saveOrRollback()
        #expect(try #require(board.changeClock) > created && board.syncDirty == true)
    }

    // MARK: Deletions

    @Test("deleting a clip remembers its plain hash and stamps the deletion")
    func deletionRemembersTheHash() async throws {
        enable()
        defer { SyncJournal.disable(for: container) }
        try await ingest("delete me")
        let id = try item("delete me").id

        try await service.deleteItems(ids: [id], reason: .user)

        let tombstone = try #require(ModelContext(container).fetch(FetchDescriptor<DeletedItemTombstone>()).first)
        let expected = Data(SHA256.hash(data: Data("delete me".utf8))).hexString
        #expect(tombstone.id == id && tombstone.plainHash == expected)
        #expect(tombstone.kindRaw == "item" && tombstone.syncDirty == true && tombstone.changeClock != nil)
    }

    @Test("with sync off a tombstone is what it always was, and retention writes none")
    func deletionWithSyncOff() async throws {
        try await ingest("a")
        try await ingest("b")
        let ids = try items().map(\.id)
        try await service.deleteItems(ids: [ids[0]], reason: .user)
        try await service.deleteItems(ids: [ids[1]], reason: .retention)

        let tombstones = try ModelContext(container).fetch(FetchDescriptor<DeletedItemTombstone>())
        #expect(tombstones.count == 1 && tombstones[0].plainHash == nil && tombstones[0].changeClock == nil)
    }

    @Test("deleting a collection leaves a stamped collection tombstone")
    func collectionDeletion() async throws {
        enable()
        defer { SyncJournal.disable(for: container) }
        let context = ModelContext(container)
        let board = Pinboard(name: "Ship", symbolName: "shippingbox", colorHex: "#2F7A49", sortOrder: 0)
        context.insert(board)
        try context.saveOrRollback()

        _ = try await service.deleteCollection(id: board.id)

        let tombstone = try #require(ModelContext(container).fetch(FetchDescriptor<DeletedItemTombstone>()).first)
        #expect(tombstone.kindRaw == "collection" && tombstone.id == board.id && tombstone.syncDirty == true)
    }

    // MARK: Eligibility

    private func clip(sensitivity: String? = nil, bytes: Int = 10, pending: Bool = false, emitted: Bool = false)
    -> ClipboardItem {
        let item = ClipboardItem(
            type: .text, previewText: "x", contentHash: "h", byteSize: bytes, deviceID: "mac-a", sequenceNumber: 1
        )
        item.sensitivityRaw = sensitivity
        item.analysisPending = pending
        item.syncEmittedClock = emitted ? "emitted" : nil
        return item
    }

    @Test("a plain clip goes; a secret waits for the person's choice; a credential and a huge clip never go")
    func eligibility() {
        #expect(SyncEligibility.verdict(for: clip(), includeSensitive: false) == .send)
        #expect(SyncEligibility
            .verdict(for: clip(sensitivity: "credit_card"), includeSensitive: false) == .staysHere(.sensitive))
        #expect(SyncEligibility.verdict(for: clip(sensitivity: "credit_card"), includeSensitive: true) == .send)
        for include in [false, true] {
            #expect(SyncEligibility
                .verdict(for: clip(sensitivity: "credential"), includeSensitive: include) == .staysHere(.credential))
            #expect(SyncEligibility
                .verdict(for: clip(bytes: 11 << 20), includeSensitive: include) == .staysHere(.tooLarge))
            #expect(SyncEligibility.verdict(for: clip(pending: true), includeSensitive: include) == .waitForJudgment)
        }
    }

    @Test("a clip that already went and is now held back needs a withdrawal; one that never went does not")
    func withdrawal() {
        #expect(SyncEligibility.needsWithdrawal(clip(sensitivity: "api_key", emitted: true), includeSensitive: false))
        #expect(!SyncEligibility.needsWithdrawal(clip(sensitivity: "api_key", emitted: true), includeSensitive: true))
        #expect(!SyncEligibility.needsWithdrawal(clip(sensitivity: "api_key", emitted: false), includeSensitive: false))
        #expect(!SyncEligibility.needsWithdrawal(clip(emitted: true), includeSensitive: false))
    }

    // MARK: Clock

    @Test("the clock never repeats a stamp, keeps going after a restart, and refuses a far-future remote stamp")
    func clock() throws {
        let fixed = Date(timeIntervalSince1970: 1_800_000_000)
        let first = SyncClock(deviceID: "mac-a", defaults: defaults, now: { fixed })
        let stamps = (0..<5).map { _ in first.next() }
        #expect(Set(stamps).count == 5 && stamps == stamps.sorted())
        let restarted = SyncClock(deviceID: "mac-a", defaults: defaults, now: { fixed })
        #expect(restarted.next() > stamps[4])
        let far = SyncStamp(wallMillis: SyncStamp.millis(fixed) + 8 * 24 * 3600 * 1000, counter: 0, deviceID: "mac-b")
        #expect(throws: SyncError.clockFarAhead) { try restarted.observe(far) }
    }

    // MARK: Migration

    @Test("a store made by 1.1.0 opens with the new columns empty and then stamps when sync is on")
    func migration() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/v1_1_0_store.store")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let copy = directory.appendingPathComponent("clips.store")
        for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: fixture.path + suffix) {
            try FileManager.default.copyItem(atPath: fixture.path + suffix, toPath: copy.path + suffix)
        }

        let opened = try ModelContainerSetup.openSynced(cloudKitEnabled: false, storeURL: copy)
        let context = ModelContext(opened)
        let clips = try context.fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.sequenceNumber)]))
        #expect(clips.count == 3 && clips.first?.previewText == "1.1.0 clip 1" && clips.first?.pinnedHotkeyIndex == 3)
        #expect(clips.allSatisfy { $0.changeClock == nil && $0.syncDirty == nil && $0.syncOrigin == nil })
        #expect(try context.fetchCount(FetchDescriptor<Pinboard>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<DeletedItemTombstone>()) == 1)

        SyncJournal.enable(for: opened, clock: SyncClock(deviceID: "mac-a", defaults: defaults))
        defer { SyncJournal.disable(for: opened) }
        clips[0].isPinned = false
        try context.saveOrRollback()
        #expect(clips[0].changeClock != nil && clips[0].syncDirty == true)
    }
}
