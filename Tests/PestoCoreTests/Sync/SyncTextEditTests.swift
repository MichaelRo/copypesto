// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("An edited clip's text reaches the other devices as the same clip", .serialized)
@MainActor
struct SyncTextEditTests {
    @Test("the edit is stamped as a change of the same clip and another device shows the new text under that id")
    func whenTextEditedOnOneDevice_thenTheOtherAppliesItToTheSameClip() async throws {
        let world = try SyncWorld(["mac-a", "mac-b"])
        let (macA, macB) = (world.macs[0], world.macs[1])
        try await world.copy("draft address line", on: macA)
        try world.setTitle("Address", of: "draft address line", on: macA)
        try await world.apply(world.publish(from: macA), on: macB)
        let id = try #require(try world.clip("draft address line", on: macA)?.id)
        let stampBefore = try #require(try world.clip("draft address line", on: macA)?.changeClock)

        world.tick()
        #expect(try await macA.service.updateText(id: id, text: "final address line") == .saved)
        let edited = try #require(try world.clip("final address line", on: macA))
        #expect(edited.syncDirty == true)
        #expect(edited.changeClock != stampBefore)

        let records = try await world.publish(from: macA)
        let items = records.filter { $0.kind == .item }
        #expect(items.count == 1)
        #expect(try items.first?.decodeMetadata(SyncItemRecord.self).id == id)
        #expect(records.allSatisfy { $0.kind != .tombstone })
        try await world.apply(records, on: macB)

        let arrived = try #require(try world.clip("final address line", on: macB))
        #expect(arrived.id == id)
        #expect(arrived.customTitle == "Address")
        #expect(try world.clip("draft address line", on: macB) == nil)
        #expect(try world.clips(on: macB).count == 1)
        #expect(try world.state(of: macA) == world.state(of: macB))
    }

    @Test("an edit to another clip's text keeps both clips on both devices, under the same ids, and a copy moves one")
    func whenEditedToAnotherClipsText_thenBothDevicesKeepBothClips() async throws {
        let world = try SyncWorld(["mac-a", "mac-b"])
        let (macA, macB) = (world.macs[0], world.macs[1])
        try await world.copy("first words", on: macA)
        try await world.copy("second words", on: macA)
        try await world.apply(world.publish(from: macA), on: macB)
        let edited = try #require(try world.clip("first words", on: macA)?.id)
        let other = try #require(try world.clip("second words", on: macA)?.id)

        world.tick()
        #expect(try await macA.service.updateText(id: edited, text: "second words") == .saved)
        try await world.apply(world.publish(from: macA), on: macB)

        for mac in [macA, macB] {
            let held = try world.clips(on: mac)
            #expect(Set(held.map(\.id)) == [edited, other], "\(mac.name)")
            #expect(held.allSatisfy { $0.blob?.decryptedText() == "second words" }, "\(mac.name)")
        }
        #expect(try world.state(of: macA) == world.state(of: macB))

        let before = try Dictionary(uniqueKeysWithValues: world.clips(on: macB).map { ($0.id, $0.timestamp) })
        let later = Date.now.addingTimeInterval(60)
        await macB.service.updateClock { later }
        try await world.copy("second words", on: macB)
        let afterCopy = try world.clips(on: macB)
        #expect(afterCopy.count == 2)
        #expect(afterCopy.first { $0.id == other }?.timestamp == later, "the clip used last moved forward")
        #expect(afterCopy.first { $0.id == edited }?.timestamp == before[edited], "the other stayed where it was")
    }

    @Test("deleting one of two clips with one text removes only that clip on the other device")
    func whenOneOfTwoClipsWithOneTextIsDeleted_thenTheOtherStaysEverywhere() async throws {
        let world = try SyncWorld(["mac-a", "mac-b"])
        let (macA, macB) = (world.macs[0], world.macs[1])
        try await world.copy("first words", on: macA)
        try await world.copy("second words", on: macA)
        try await world.apply(world.publish(from: macA), on: macB)
        let edited = try #require(try world.clip("first words", on: macA)?.id)
        let other = try #require(try world.clip("second words", on: macA)?.id)
        world.tick()
        try await macA.service.updateText(id: edited, text: "second words")
        try await world.apply(world.publish(from: macA), on: macB)

        world.tick()
        try await macA.service.deleteItems(ids: [edited], reason: .user)
        let removal = try await world.publish(from: macA)
        let tombstone = try #require(try removal.first { $0.kind == .tombstone }?
            .decodeMetadata(SyncTombstoneRecord.self))
        #expect(tombstone.id == edited)
        #expect(tombstone.plainHash == nil, "the text lives on in another clip, so the deletion names only the id")
        try await world.apply(removal, on: macB)

        #expect(try world.clips(on: macB).map(\.id) == [other])
        #expect(try world.state(of: macA) == world.state(of: macB))

        world.tick()
        try await macA.service.deleteItems(ids: [other], reason: .user)
        let last = try await world.publish(from: macA)
        let lastTombstone = try #require(try last.first { $0.kind == .tombstone }?
            .decodeMetadata(SyncTombstoneRecord.self))
        #expect(lastTombstone.plainHash != nil, "the last clip with the text names it, as before")
        try await world.apply(last, on: macB)
        #expect(try world.clips(on: macB).isEmpty)
    }

    @Test("a later edit of one of two clips with one text changes only that clip on the other device")
    func whenOneOfTwoClipsWithOneTextIsEditedAgain_thenOnlyItChanges() async throws {
        let world = try SyncWorld(["mac-a", "mac-b"])
        let (macA, macB) = (world.macs[0], world.macs[1])
        try await world.copy("first words", on: macA)
        try await world.copy("second words", on: macA)
        try await world.apply(world.publish(from: macA), on: macB)
        let edited = try #require(try world.clip("first words", on: macA)?.id)
        let other = try #require(try world.clip("second words", on: macA)?.id)
        world.tick()
        try await macA.service.updateText(id: edited, text: "second words")
        try await world.apply(world.publish(from: macA), on: macB)

        try await world.pin("second words", on: macB)
        let pinnedID = try #require(try world.clips(on: macB).first { $0.isPinned }?.id)
        try await world.apply(world.publish(from: macB), on: macA)
        world.tick()
        try await macA.service.updateText(id: edited, text: "third words")
        try await world.apply(world.publish(from: macA), on: macB)

        #expect(try world.clips(on: macB).first { $0.id == edited }?.blob?.decryptedText() == "third words")
        #expect(try world.clips(on: macB).first { $0.id == other }?.blob?.decryptedText() == "second words")
        #expect(try world.clips(on: macA).first { $0.id == pinnedID }?.isPinned == true)
        #expect(try world.state(of: macA) == world.state(of: macB))
    }
}
