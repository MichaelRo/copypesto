// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("Pinned clip shortcuts (⌃1 to ⌃9)")
struct HotkeySlotStorageTests {
    private let container: ModelContainer

    init() throws {
        container = try ModelContainerSetup.makeInMemory().synced
    }

    private func service() async -> StorageService {
        StorageService(modelContainer: container)
    }

    private func clip(_ id: UUID) throws -> ClipboardItem {
        try #require(ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first { $0.id == id })
    }

    private func makeClip(_ service: StorageService, _ text: String) async throws -> UUID {
        try #require(await service.addSnippet(text))
    }

    @Test("giving a clip a shortcut pins it, so it cannot be pruned and the shortcut is live")
    func assign_pinsAnUnpinnedClip() async throws {
        let service = await service()
        let id = try #require(await service.addSnippet("plain clip"))
        _ = try await service.togglePinned(id: id)
        #expect(try clip(id).isPinned == false)

        #expect(try await service.assignHotkeySlot(3, to: id))

        let item = try clip(id)
        #expect(item.isPinned)
        #expect(item.pinnedHotkeyIndex == 3)
    }

    @Test("a shortcut belongs to one clip: giving it to another takes it from the first")
    func assign_movesTheSlotFromTheOtherClip() async throws {
        let service = await service()
        let first = try await makeClip(service, "first")
        let second = try await makeClip(service, "second")
        _ = try await service.assignHotkeySlot(2, to: first)

        _ = try await service.assignHotkeySlot(2, to: second)

        #expect(try clip(first).pinnedHotkeyIndex == nil)
        #expect(try clip(second).pinnedHotkeyIndex == 2)
    }

    @Test("removing the shortcut leaves the clip pinned")
    func assignNil_clearsTheSlotOnly() async throws {
        let service = await service()
        let id = try await makeClip(service, "keep")
        _ = try await service.assignHotkeySlot(5, to: id)

        #expect(try await service.assignHotkeySlot(nil, to: id))

        let item = try clip(id)
        #expect(item.pinnedHotkeyIndex == nil)
        #expect(item.isPinned)
    }

    @Test("unpinning a clip frees its shortcut, because a shortcut only works for a pinned clip")
    func unpin_clearsTheSlot() async throws {
        let service = await service()
        let id = try await makeClip(service, "unpin me")
        _ = try await service.assignHotkeySlot(7, to: id)

        let pinned = try await service.togglePinned(id: id)

        #expect(pinned == false)
        #expect(try clip(id).pinnedHotkeyIndex == nil)
    }

    @Test("only slots 1 to 9 exist, and a clip that is not there is not changed")
    func assign_rejectsWhatDoesNotExist() async throws {
        let service = await service()
        let id = try await makeClip(service, "x")

        #expect(try await service.assignHotkeySlot(0, to: id) == false)
        #expect(try await service.assignHotkeySlot(10, to: id) == false)
        #expect(try await service.assignHotkeySlot(1, to: UUID()) == false)
        #expect(try clip(id).pinnedHotkeyIndex == nil)
    }
}
