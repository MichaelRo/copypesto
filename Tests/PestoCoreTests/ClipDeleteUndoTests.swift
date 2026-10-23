// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("Undoing a delete puts the clip back exactly as it was", .serialized)
struct ClipDeleteUndoTests {
    private let container: ModelContainer
    private let service: StorageService
    private let history = UndoHistory()

    init() async throws {
        container = try ModelContainerSetup.makeInMemory().synced
        service = StorageService(modelContainer: container, environment: .testing { [history] in
            $0.undoHistory = history
        })
    }

    private func capture(_ text: String, at offset: TimeInterval = 0) -> PasteboardCapture {
        PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
            timestamp: .now.addingTimeInterval(offset), contentHash: "hash-\(text)"
        )
    }

    private func items() throws -> [ClipboardItem] {
        try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
    }

    private func ingest(_ texts: String...) async throws -> [UUID] {
        for (index, text) in texts.enumerated() {
            try await service.ingest(capture(text, at: Double(index)))
        }
        let byText = try Dictionary(uniqueKeysWithValues: items().map { ($0.displayPreviewText, $0.id) })
        return try texts.map { try #require(byText[$0]) }
    }

    @Test("a deleted clip comes back with its text, its id, its time and no tombstone")
    func whenUndone_thenTheClipIsBack() async throws {
        let ids = try await ingest("keep me", "restore me")
        let original = try #require(items().first { $0.id == ids[1] })
        let timestamp = original.timestamp
        let hash = original.contentHash

        try await service.deleteItems(ids: [ids[1]], reason: .user)
        #expect(try items().count == 1)
        #expect(history.undoLabel == .deleteClips(1))

        let outcome = try await service.undo()

        #expect(outcome == UndoOutcome(label: .deleteClips(1), direction: .undone))
        let restored = try #require(items().first { $0.id == ids[1] })
        #expect(restored.displayPreviewText == "restore me")
        #expect(restored.timestamp == timestamp && restored.contentHash == hash)
        #expect(restored.blob?.decryptedText() == "restore me")
        #expect(try ModelContext(container).fetch(FetchDescriptor<DeletedItemTombstone>()).isEmpty)
    }

    @Test("redo deletes it again, with its tombstone, and a second undo brings it back again")
    func whenRedone_thenDeletedAgain() async throws {
        let ids = try await ingest("one", "two")
        try await service.deleteItems(ids: ids, reason: .user)
        _ = try await service.undo()
        #expect(try items().count == 2)

        let redone = try await service.redo()

        #expect(redone?.direction == .redone)
        #expect(try items().isEmpty)
        #expect(try ModelContext(container).fetch(FetchDescriptor<DeletedItemTombstone>()).count == 2)
        #expect(history.redoLabel == nil && history.undoLabel == .deleteClips(2))
        _ = try await service.undo()
        #expect(try items().count == 2)
    }

    @Test("every column is restored: pins, shortcuts, collections, titles, notes, counts and flags")
    func whenUndone_thenEveryColumnMatches() async throws {
        let id = try #require(await ingest("everything").first)
        let board = UUID()
        let context = ModelContext(container)
        let item = try #require(context.fetch(FetchDescriptor<ClipboardItem>()).first)
        item.isPinned = true
        item.pinnedHotkeyIndex = 3
        item.collectionID = board
        item.pasteCount = 7
        item.isNSFW = true
        item.customTitle = "A title"
        item.userNote = "A note"
        item.tags = ["one", "two"]
        item.detectedLanguage = "swift"
        item.pixelWidth = 12
        item.pixelHeight = 34
        try context.save()
        let expected = ClipFieldState(item)
        let sequence = item.sequenceNumber
        let device = item.deviceID

        try await service.deleteItems(ids: [id], reason: .user)
        _ = try await service.undo()

        let restored = try #require(items().first)
        #expect(ClipFieldState(restored) == expected)
        #expect(restored.pasteCount == 7 && restored.detectedLanguage == "swift")
        #expect(restored.pixelWidth == 12 && restored.pixelHeight == 34)
        #expect(restored.sequenceNumber == sequence && restored.deviceID == device)
        #expect(restored.blob?.decryptedText() == "everything")
    }

    @Test("a snapshot copies every stored column of a clip, so a new column fails here until it is copied")
    func whenTheModelGrows_thenTheSnapshotMustFollow() throws {
        let entity = try #require(Schema([ClipboardItem.self, ClipboardBlob.self]).entities
            .first { $0.name == "ClipboardItem" })
        let stored = Set(entity.storedProperties.map(\.name))
        #expect(stored == ClipSnapshot.coveredColumns)
    }

    @Test("only a deletion the person made can be undone")
    func whenNotUser_thenNothingIsKept() async throws {
        let ids = try await ingest("aged", "cleared")

        try await service.deleteItems(ids: [ids[0]], reason: .retention)
        try await service.deleteItems(ids: [ids[1]], reason: .clear)

        #expect(history.undoLabel == nil)
    }

    @Test("a clip that expires, or is too large, is deleted for good")
    func whenNotHoldable_thenNoUndo() async throws {
        let ids = try await ingest("burns", "huge", "fine")
        let context = ModelContext(container)
        let all = try context.fetch(FetchDescriptor<ClipboardItem>())
        try #require(all.first { $0.id == ids[0] }).expiresAt = .now.addingTimeInterval(60)
        try #require(all.first { $0.id == ids[1] }).byteSize = UndoPolicy.maxClipBytes + 1
        try context.save()

        try await service.deleteItems(ids: [ids[0]], reason: .user)
        #expect(history.undoLabel == nil)
        try await service.deleteItems(ids: [ids[1]], reason: .user)
        #expect(history.undoLabel == nil)
        try await service.deleteItems(ids: [ids[2]], reason: .user)
        #expect(history.undoLabel == .deleteClips(1))
    }

    @Test("a batch with one clip that cannot be held is not undoable at all")
    func whenOneIsNotHoldable_thenTheBatchIsNot() async throws {
        let ids = try await ingest("burns", "fine")
        let context = ModelContext(container)
        try #require(context.fetch(FetchDescriptor<ClipboardItem>()).first { $0.id == ids[0] })
            .expiresAt = .now.addingTimeInterval(60)
        try context.save()

        try await service.deleteItems(ids: ids, reason: .user)

        #expect(history.undoLabel == nil)
    }

    @Test("a clip copied again while the old one was deleted is not duplicated by the undo")
    func whenCopiedAgain_thenNoDuplicate() async throws {
        let ids = try await ingest("same words")
        try await service.deleteItems(ids: ids, reason: .user)
        try await service.ingest(capture("same words", at: 10))

        _ = try await service.undo()

        #expect(try items().count == 1)
    }

    @Test("a shortcut another clip took meanwhile stays with that clip")
    func whenTheSlotIsTaken_thenTheRestoredClipHasNone() async throws {
        let ids = try await ingest("first", "second")
        try await service.assignHotkeySlot(4, to: ids[0])
        try await service.deleteItems(ids: [ids[0]], reason: .user)
        let context = ModelContext(container)
        try #require(context.fetch(FetchDescriptor<ClipboardItem>()).first { $0.id == ids[1] })
            .pinnedHotkeyIndex = 4
        try context.save()

        _ = try await service.undo()

        let byID = try Dictionary(uniqueKeysWithValues: items().map { ($0.id, $0) })
        #expect(byID[ids[0]]?.pinnedHotkeyIndex == nil)
        #expect(byID[ids[1]]?.pinnedHotkeyIndex == 4)
    }

    @Test("undo goes back one action at a time, newest first, across deletes and edits")
    func whenSeveralActions_thenNewestFirst() async throws {
        let ids = try await ingest("one", "two")
        try await service.deleteItems(ids: [ids[0]], reason: .user)
        try await service.togglePinned(id: ids[1])
        #expect(history.undoLabel == .changeClip(.pinned))

        #expect(try await service.undo()?.label == .changeClip(.pinned))
        #expect(try items().first { $0.id == ids[1] }?.isPinned == false)
        #expect(try await service.undo()?.label == .deleteClips(1))
        #expect(try items().count == 2)
        #expect(try await service.redo()?.label == .deleteClips(1))
        #expect(try items().count == 1)
        #expect(try await service.redo()?.label == .changeClip(.pinned))
        #expect(try items().first?.isPinned == true)
    }

    @Test("Clear History and Clear Everything forget what could be undone")
    func whenCleared_thenTheStackIsEmpty() async throws {
        let ids = try await ingest("a", "b", "c")
        try await service.deleteItems(ids: [ids[0]], reason: .user)
        #expect(history.undoLabel != nil)
        try await service.clearNonPinned(in: .all)
        #expect(history.undoLabel == nil)

        let more = try await ingest("d")
        try await service.deleteItems(ids: more, reason: .user)
        #expect(history.undoLabel != nil)
        try await service.clearEverything()
        #expect(history.undoLabel == nil)
        #expect(try await service.undo() == nil)
    }
}
