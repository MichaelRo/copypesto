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
}
