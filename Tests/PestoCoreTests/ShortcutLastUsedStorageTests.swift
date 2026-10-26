// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("Shortcut last used column and storage operations")
struct ShortcutLastUsedStorageTests {
    private let container: ModelContainer
    private let calendar = Calendar.current

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

    @Test("when shortcut assigned, last used is today")
    func whenShortcutAssigned_thenLastUsedIsToday() async throws {
        let service = await service()
        let id = try await makeClip(service, "snippet")
        _ = try await service.assignHotkeySlot(3, to: id)

        let item = try clip(id)
        #expect(item.pinnedHotkeyIndex == 3)
        #expect(item.shortcutLastUsedAt == calendar.startOfDay(for: .now))
    }

    @Test("when shortcut cleared, last used is nil")
    func whenShortcutCleared_thenLastUsedNil() async throws {
        let service = await service()
        let id = try await makeClip(service, "snippet")
        _ = try await service.assignHotkeySlot(3, to: id)
        _ = try await service.assignHotkeySlot(nil, to: id)

        let item = try clip(id)
        #expect(item.pinnedHotkeyIndex == nil)
        #expect(item.shortcutLastUsedAt == nil)
    }

    @Test("when slot stolen by another clip, previous holder column is nil")
    func whenSlotStolen_thenPreviousHolderColumnNil() async throws {
        let service = await service()
        let first = try await makeClip(service, "first")
        let second = try await makeClip(service, "second")

        _ = try await service.assignHotkeySlot(2, to: first)
        #expect(try clip(first).shortcutLastUsedAt != nil)

        _ = try await service.assignHotkeySlot(2, to: second)
        #expect(try clip(first).pinnedHotkeyIndex == nil)
        #expect(try clip(first).shortcutLastUsedAt == nil)
        #expect(try clip(second).pinnedHotkeyIndex == 2)
        #expect(try clip(second).shortcutLastUsedAt == calendar.startOfDay(for: .now))
    }

    @Test("when unpinned, column is nil")
    func whenUnpinned_thenColumnNil() async throws {
        let service = await service()
        let id = try await makeClip(service, "pinned")
        _ = try await service.assignHotkeySlot(1, to: id)
        _ = try await service.togglePinned(id: id)

        let item = try clip(id)
        #expect(!item.isPinned)
        #expect(item.pinnedHotkeyIndex == nil)
        #expect(item.shortcutLastUsedAt == nil)
    }

    @Test("when shortcut used twice on the same day, second write is skipped")
    func whenUsedTwiceSameDay_thenSecondWriteSkipped() async throws {
        let service = await service()
        let id = try await makeClip(service, "used")
        _ = try await service.assignHotkeySlot(1, to: id)

        let initialDate = try clip(id).shortcutLastUsedAt
        try await service.noteShortcutUsed(id: id)
        #expect(try clip(id).shortcutLastUsedAt == initialDate)
    }

    @Test("when noteShortcutUsed called on clip without shortcut, nothing written")
    func whenNoteShortcutUsedOnClipWithoutShortcut_thenNothingWritten() async throws {
        let service = await service()
        let id = try await makeClip(service, "no shortcut")
        _ = try await service.togglePinned(id: id)

        try await service.noteShortcutUsed(id: id)
        #expect(try clip(id).shortcutLastUsedAt == nil)
    }

    @Test("assignFreeHotkeySlot refuses when held by another clip and assigns when free")
    func whenAssignFreeSlot_thenBehavesCorrectly() async throws {
        let service = await service()
        let first = try await makeClip(service, "first")
        let second = try await makeClip(service, "second")

        _ = try await service.assignHotkeySlot(5, to: first)

        let takenRes = try await service.assignFreeHotkeySlot(5, to: second)
        #expect(takenRes == .slotTaken)
        #expect(try clip(second).pinnedHotkeyIndex == nil)

        let freeRes = try await service.assignFreeHotkeySlot(6, to: second)
        #expect(freeRes == .assigned)
        #expect(try clip(second).pinnedHotkeyIndex == 6)
        #expect(try clip(second).isPinned)
        #expect(try clip(second).shortcutLastUsedAt == calendar.startOfDay(for: .now))
    }

    @Test("assignFree records undo and undo restores both pin and shortcut")
    func whenAssignFree_thenUndoRestoresBothPinAndShortcut() async throws {
        let service = await service()
        let id = try await makeClip(service, "undoable")
        _ = try await service.togglePinned(id: id) // unpin

        let res = try await service.assignFreeHotkeySlot(7, to: id)
        #expect(res == .assigned)
        #expect(try clip(id).pinnedHotkeyIndex == 7)
        #expect(try clip(id).shortcutLastUsedAt != nil)

        try await service.undo()
        let undone = try clip(id)
        #expect(undone.pinnedHotkeyIndex == nil)
        #expect(undone.shortcutLastUsedAt == nil)
        #expect(!undone.isPinned)

        try await service.redo()
        let redone = try clip(id)
        #expect(redone.pinnedHotkeyIndex == 7)
        #expect(redone.shortcutLastUsedAt != nil)
        #expect(redone.isPinned)
    }
}
