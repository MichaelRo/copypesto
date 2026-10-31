// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Synchronization
import Testing
@testable import PestoCore

final class TimeBox: Sendable {
    private let value = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
    var now: Date {
        value.withLock { $0 }
    }

    func advance(by seconds: TimeInterval = 1) {
        value.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}

/// Three simulated Macs, each with its own store, clock and key, and a log they publish to.
@MainActor
final class SyncWorld {
    final class Mac {
        let name: String
        let container: ModelContainer
        let service: StorageService
        let clock: SyncClock

        init(name: String, time: TimeBox) throws {
            self.name = name
            container = try ModelContainerSetup.makeInMemory()
            service = StorageService(modelContainer: container)
            clock = SyncClock(deviceID: name, defaults: ThrowawayDefaults.make(), now: { time.now })
            SyncJournal.enable(for: container, clock: clock)
        }

        deinit { SyncJournal.disable(for: container) }
    }

    let time = TimeBox()
    let key = SyncKey.generate()
    var macs: [Mac] = []
    var log: [SyncRecord] = []
    var blobs: [String: Data] = [:]

    init(_ names: [String] = ["mac-a", "mac-b", "mac-c"]) throws {
        macs = try names.map { try Mac(name: $0, time: time) }
    }

    func tick() {
        time.advance()
    }

    func copy(_ text: String, on mac: Mac) async throws {
        tick()
        let payload = Data(text.utf8)
        try await mac.service.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: payload, payloadString: text,
            frontmostBundleID: "com.apple.Notes", timestamp: time.now,
            contentHash: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        ))
    }

    func clips(on mac: Mac) throws -> [ClipboardItem] {
        try ModelContext(mac.container).fetch(FetchDescriptor<ClipboardItem>())
    }

    func clip(_ text: String, on mac: Mac) throws -> ClipboardItem? {
        try clips(on: mac).first { $0.blob?.decryptedText() == text }
    }

    func setTitle(_ title: String?, of text: String, on mac: Mac) throws {
        tick()
        let context = ModelContext(mac.container)
        guard let item = try context.fetch(FetchDescriptor<ClipboardItem>())
            .first(where: { $0.blob?.decryptedText() == text }) else { return }
        item.customTitle = title
        try context.saveOrRollback()
    }

    func pin(_ text: String, on mac: Mac) async throws {
        tick()
        if let item = try clip(text, on: mac) { _ = try await mac.service.togglePinned(id: item.id) }
    }

    func delete(_ text: String, on mac: Mac) async throws {
        tick()
        if let item = try clip(text, on: mac) { try await mac.service.deleteItems(ids: [item.id], reason: .user) }
    }

    @discardableResult
    func publish(from mac: Mac, includeSensitive: Bool = false) async throws -> [SyncRecord] {
        tick()
        let outbox = try await mac.service.buildOutbox(includeSensitive: includeSensitive, syncKey: key)
        blobs.merge(outbox.blobs) { $1 }
        try await mac.service.commitOutbox(outbox)
        log += outbox.records
        return outbox.records
    }

    func apply(_ records: [SyncRecord], on mac: Mac) async throws {
        let files = blobs
        _ = try await mac.service.applySync(records, blob: { files[$0] })
    }

    /// What a person sees on this Mac: each clip's text, title and pin, and the collections' names.
    func state(of mac: Mac) throws -> [String] {
        let context = ModelContext(mac.container)
        let items = try context.fetch(FetchDescriptor<ClipboardItem>()).map {
            "\($0.blob?.decryptedText() ?? "?")|\($0.customTitle ?? "-")|\($0.isPinned)"
        }
        let boards = try context.fetch(FetchDescriptor<Pinboard>()).map { "board|\($0.name)" }
        return (items + boards).sorted()
    }
}

@Suite("Sync merge: the same clips and edits on every Mac, whatever the order they arrive in", .serialized)
@MainActor
struct SyncMergeTests {
    @Test("a clip written on one Mac appears on another with the same id, and applying it again changes nothing")
    func basic() async throws {
        let world = try SyncWorld()
        let (a, b) = (world.macs[0], world.macs[1])
        try await world.copy("hello", on: a)
        try world.setTitle("Greeting", of: "hello", on: a)
        let records = try await world.publish(from: a)

        try await world.apply(records, on: b)
        try await world.apply(records, on: b)

        #expect(try world.state(of: a) == world.state(of: b))
        #expect(try world.clip("hello", on: b)?.customTitle == "Greeting")
        let outbox = try await b.service.buildOutbox(includeSensitive: false, syncKey: world.key)
        #expect(outbox.records.isEmpty, "what arrived from another Mac is not written back")
    }

    @Test("a deletion removes the clip elsewhere; an old record cannot bring it back; a later copy can")
    func deletion() async throws {
        let world = try SyncWorld()
        let (a, b) = (world.macs[0], world.macs[1])
        try await world.copy("gone", on: a)
        let first = try await world.publish(from: a)
        try await world.apply(first, on: b)

        try await world.delete("gone", on: b)
        let removal = try await world.publish(from: b)
        try await world.apply(removal, on: a)
        #expect(try world.clip("gone", on: a) == nil)

        try await world.apply(first, on: a)
        try await world.apply(first, on: b)
        #expect(
            try world.clip("gone", on: a) == nil && world.clip("gone", on: b) == nil,
            "an old record resurrected it"
        )

        try await world.copy("spacer", on: a)
        try await world.copy("gone", on: a)
        let again = try await world.publish(from: a)
        try await world.apply(again, on: b)
        #expect(try world.clip("gone", on: b) != nil, "copying it again is a new decision")
    }

    @Test("an edit made after the deletion survives it; an edit made before does not")
    func editAgainstDeletion() async throws {
        let world = try SyncWorld()
        let (a, b) = (world.macs[0], world.macs[1])
        try await world.copy("contested", on: a)
        let created = try await world.publish(from: a)
        try await world.apply(created, on: b)
        try world.setTitle("old edit", of: "contested", on: a)
        let oldEdit = try await world.publish(from: a)
        try await world.delete("contested", on: b)
        let removal = try await world.publish(from: b)
        try world.setTitle("late edit", of: "contested", on: a)
        let lateEdit = try await world.publish(from: a)

        for mac in [a, b] {
            try await world.apply(oldEdit + removal, on: mac)
        }
        #expect(try world.clip("contested", on: b) == nil)
        for mac in [a, b] {
            try await world.apply(lateEdit, on: mac)
        }
        #expect(try world.clip("contested", on: b)?.customTitle == "late edit")
        #expect(try world.state(of: a) == world.state(of: b))
    }

    @Test("two Macs that copy the same text end with one clip")
    func twins() async throws {
        let world = try SyncWorld()
        let (a, b) = (world.macs[0], world.macs[1])
        try await world.copy("same words", on: b)
        try await world.copy("same words", on: a)
        let fromA = try await world.publish(from: a), fromB = try await world.publish(from: b)

        try await world.apply(fromB, on: a)
        try await world.apply(fromA, on: b)

        #expect(try world.clips(on: a).count == 1 && world.clips(on: b).count == 1)
        #expect(try world.state(of: a) == world.state(of: b))
    }

    @Test("a collection and its rename travel, and deleting it removes it elsewhere")
    func collections() async throws {
        let world = try SyncWorld()
        let (a, b) = (world.macs[0], world.macs[1])
        let context = ModelContext(a.container)
        let board = Pinboard(name: "Ship", symbolName: "shippingbox", colorHex: "#2F7A49", sortOrder: 0)
        context.insert(board)
        try context.saveOrRollback()
        try await world.apply(world.publish(from: a), on: b)
        #expect(try world.state(of: b).contains { $0.hasSuffix("|Ship") })

        world.tick()
        board.name = "Shipping"
        try context.saveOrRollback()
        try await world.apply(world.publish(from: a), on: b)
        #expect(try world.state(of: a) == world.state(of: b))

        _ = try await a.service.deleteCollection(id: board.id)
        try await world.apply(world.publish(from: a), on: b)
        #expect(try ModelContext(b.container).fetchCount(FetchDescriptor<Pinboard>()) == 0)
    }

    @Test(
        "a secret is held back unless the person chose it, and withdrawn when it stops being allowed"
    )
    func secrets() async throws {
        let world = try SyncWorld()
        let (a, b) = (world.macs[0], world.macs[1])
        try await world.copy("4111 1111 1111 1111", on: a)
        try await world.copy("plain note", on: a)
        let held = try await world.publish(from: a)
        #expect(held.count == 1, "only the plain clip went")

        try await world.apply(held, on: b)
        _ = try await a.service.restampForSync(.sensitive)
        let both = try await world.publish(from: a, includeSensitive: true)
        #expect(both.count == 1, "only the clip that was held back goes now; the plain one went before")
        try await world.apply(both, on: b)
        #expect(try world.clips(on: b).count == 2)

        _ = try await a.service.restampForSync(.sensitive)
        let withdrawn = try await world.publish(from: a, includeSensitive: false)
        try await world.apply(withdrawn, on: b)
        #expect(try world.clips(on: b).count == 1, "the secret was withdrawn from the other Mac")
        #expect(try world.clips(on: a).count == 2, "and kept here")
    }

    @Test("a payload over the inline limit travels as a named file and applies from it")
    func bigPayload() async throws {
        let world = try SyncWorld()
        let (a, b) = (world.macs[0], world.macs[1])
        let big = String(repeating: "pesto ", count: 60_000)
        try await world.copy(big, on: a)
        let judging = ModelContext(a.container)
        try judging.fetch(FetchDescriptor<ClipboardItem>()).forEach { $0.analysisPending = false }
        try judging.saveOrRollback()
        let records = try await world.publish(from: a)
        let pending = try world.clips(on: a).map(\.analysisPending)
        #expect(!records.isEmpty, "no records; pending \(pending)")
        let meta = try #require(try records.first?.decodeMetadata(SyncItemRecord.self))
        #expect(meta.blobName != nil && records[0].payload.isEmpty)
        try await world.apply(records, on: b)
        #expect(try world.clip(big, on: b) != nil)
    }

    // MARK: Convergence

    struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    @Test(
        "random copies, edits, pins and deletions on three Macs converge, delivered one record at a time in any order",
        arguments: [1, 2, 3, 4, 5, 6, 7, 8]
    )
    func convergence(seed: UInt64) async throws {
        var random = SeededGenerator(state: seed)
        let world = try SyncWorld()
        let texts = ["alpha", "beta", "gamma", "delta", "epsilon"]
        for _ in 0..<60 {
            let mac = world.macs.randomElement(using: &random) ?? world.macs[0]
            let text = texts.randomElement(using: &random) ?? "alpha"
            switch Int.random(in: 0..<8, using: &random) {
            case 0, 1: try await world.copy(text, on: mac)
            case 2: try world.setTitle("t\(Int.random(in: 0..<5, using: &random))", of: text, on: mac)
            case 3: try await world.pin(text, on: mac)
            case 4: try await world.delete(text, on: mac)
            case 5: try await world.publish(from: mac)
            default:
                let other = world.macs.randomElement(using: &random) ?? mac
                let slice = Array(world.log.shuffled(using: &random).prefix(6))
                if other !== mac { try await world.apply(slice, on: other) }
            }
        }
        for mac in world.macs {
            try await world.publish(from: mac)
        }
        for mac in world.macs {
            var delivery = world.log + world.log.shuffled(using: &random).prefix(10)
            delivery.shuffle(using: &random)
            for record in delivery {
                try await world.apply([record], on: mac)
            }
        }
        let states = try world.macs.map { try world.state(of: $0) }
        let same = states[0] == states[1] && states[1] == states[2]
        #expect(same, "seed \(seed):\nA \(states[0])\nB \(states[1])\nC \(states[2])")
    }
}
