// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("Sync carries when a clip was first copied", .serialized)
@MainActor
struct SyncCopiedAtTests {
    private func use(_ text: String, on mac: SyncWorld.Mac, world: SyncWorld) throws -> Date {
        world.tick()
        let context = ModelContext(mac.container)
        let item = try #require(try context.fetch(FetchDescriptor<ClipboardItem>())
            .first { $0.blob?.decryptedText() == text })
        item.bringToFront(at: world.time.now)
        try context.saveOrRollback()
        return world.time.now
    }

    @Test("a clip pasted on one Mac arrives on another dated by its last use but placed by its first copy")
    func whenPastedBeforeSync_thenFirstCopyTravels() async throws {
        let world = try SyncWorld()
        let (a, b) = (world.macs[0], world.macs[1])
        try await world.copy("hello", on: a)
        let firstCopy = try #require(try world.clip("hello", on: a)).timestamp
        let lastUse = try use("hello", on: a, world: world)

        try await world.apply(world.publish(from: a), on: b)

        let arrived = try #require(try world.clip("hello", on: b))
        #expect(arrived.timestamp == lastUse)
        #expect(arrived.copiedAt == firstCopy)
    }

    @Test("a clip never used travels without a first-copy time, and nothing is sealed for it on the other Mac")
    func whenNeverUsed_thenNothingSealed() async throws {
        let world = try SyncWorld()
        let (a, b) = (world.macs[0], world.macs[1])
        try await world.copy("plain", on: a)

        try await world.apply(world.publish(from: a), on: b)

        let arrived = try #require(try world.clip("plain", on: b))
        #expect(arrived.metadata.copiedAt == nil)
        #expect(arrived.copiedAt == arrived.timestamp)
    }

    @Test("a paste after the clip has synced writes no record: it is this Mac's own business")
    func whenPastedAfterSync_thenNothingToPublish() async throws {
        let world = try SyncWorld()
        let a = world.macs[0]
        try await world.copy("hello", on: a)
        try await world.publish(from: a)
        _ = try use("hello", on: a, world: world)

        let records = try await world.publish(from: a)

        #expect(records.isEmpty)
    }

    @Test("two Macs that copied the same text end with the earlier first copy on both, once the earlier Mac writes a record")
    func whenBothCopied_thenEarlierFirstCopyWins() async throws {
        let world = try SyncWorld()
        let (a, b) = (world.macs[0], world.macs[1])
        try await world.copy("shared", on: a)
        let earlier = try #require(try world.clip("shared", on: a)).timestamp
        try await world.copy("shared", on: b)
        try world.setTitle("T", of: "shared", on: b)

        try await world.apply(world.publish(from: b), on: a)
        try world.setTitle("From A", of: "shared", on: a)
        try await world.apply(world.publish(from: a), on: b)

        #expect(try world.clip("shared", on: a)?.copiedAt == earlier)
        #expect(try world.clip("shared", on: b)?.copiedAt == earlier)
    }

    @Test("a record written before the field existed still applies")
    func whenOldRecord_thenDecodes() throws {
        let old = Data(#"{"tags":[],"isPinned":false}"#.utf8)
        let curation = try JSONDecoder().decode(SyncCuration.self, from: old)
        #expect(curation.copiedAt == nil)
    }
}
