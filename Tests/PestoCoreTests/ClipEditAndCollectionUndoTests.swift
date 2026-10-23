// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("Undoing an edit or a deleted collection", .serialized)
@MainActor
struct ClipEditAndCollectionUndoTests {
    private let container: ModelContainer
    private let service: StorageService
    private let history = UndoHistory()

    init() async throws {
        container = try ModelContainerSetup.makeInMemory().synced
        service = StorageService(modelContainer: container, environment: .testing { [history] in
            $0.undoHistory = history
        })
    }

    private func editor() -> ClipEditor {
        ClipEditor(
            context: container.mainContext, historyStore: nil, report: { _, work in try? work() }, didEdit: {},
            undoHistory: history
        )
    }

    private func ingestOne() async throws -> ClipboardItem {
        try await service.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data("hello".utf8), payloadString: "hello",
            timestamp: .now, contentHash: "hash-hello"
        ))
        return try #require(container.mainContext.fetch(FetchDescriptor<ClipboardItem>()).first)
    }

    @Test("an edit is undone field by field, and a background change to the same clip is left alone")
    func whenEditUndone_thenOnlyThePersonsFieldsGoBack() async throws {
        let item = try await ingestOne()
        editor().edit(item) {
            $0.customTitle = "My title"
            $0.isNSFW = true
        }
        #expect(history.undoLabel == .changeClip(.title))
        item.updateMetadata { $0.ogTitle = "Fetched page title" }
        try container.mainContext.save()

        let undone = try await service.undo()

        #expect(undone?.label == .changeClip(.title))
        let fresh = try #require(ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first)
        #expect(fresh.customTitle == nil && fresh.isNSFW == false)
        #expect(fresh.ogTitle == "Fetched page title")

        _ = try await service.redo()
        let again = try #require(ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first)
        #expect(again.customTitle == "My title" && again.isNSFW)
    }

    @Test("a change the app derives (a fetched link preview) is saved, reaches the shelf, and is not an undoable edit")
    func whenDerivedChange_thenSavedAndNotUndoable() async throws {
        let item = try await ingestOne()
        var shelfToldItMoved = 0
        var reported = 0
        let editor = ClipEditor(
            context: container.mainContext, historyStore: nil, report: { _, work in
                reported += 1
                try? work()
            }, didEdit: { shelfToldItMoved += 1 }, undoHistory: history
        )
        let recorded = history.recordedCount

        editor.applyDerived(to: item, changesFilter: true) {
            $0.updateMetadata { $0.ogTitle = "Fetched page title" }
            $0.linkPreviewFetched = true
        }

        let fresh = try #require(ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first)
        #expect(fresh.ogTitle == "Fetched page title" && fresh.linkPreviewFetched)
        #expect(history.recordedCount == recorded, "a derived field is not something the person can undo")
        #expect(shelfToldItMoved == 1)
        #expect(reported == 0, "a save that worked says nothing")
    }

    @Test("an edit that changes nothing records nothing")
    func whenNothingChanged_thenNothingIsKept() async throws {
        let item = try await ingestOne()

        editor().edit(item) { _ in }

        #expect(history.undoLabel == nil)
    }

    @Test("moving a clip into a collection can be undone")
    func whenMovedToACollection_thenUndoMovesItBack() async throws {
        let item = try await ingestOne()
        let board = UUID()

        editor().edit(item) { $0.collectionID = board }
        #expect(history.undoLabel == .changeClip(.collection))
        _ = try await service.undo()

        let fresh = try #require(ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first)
        #expect(fresh.collectionID == nil)
    }

    @Test("a deleted collection comes back with its settings, and its clips are in it again")
    func whenCollectionDeleted_thenUndoRestoresIt() async throws {
        let item = try await ingestOne()
        let board = Pinboard(
            name: "Work", symbolName: "briefcase", colorHex: "#112233", sortOrder: 4, isSmart: true,
            smartPredicateData: Data([1, 2, 3]), triggerBundleID: "com.apple.Notes"
        )
        container.mainContext.insert(board)
        item.collectionID = board.id
        try container.mainContext.save()

        #expect(try await service.deleteCollection(id: board.id))
        #expect(try ModelContext(container).fetch(FetchDescriptor<Pinboard>()).isEmpty)
        #expect(history.undoLabel == .deleteCollection("Work"))
        _ = try await service.undo()

        let restored = try #require(ModelContext(container).fetch(FetchDescriptor<Pinboard>()).first)
        #expect(restored.id == board.id && restored.name == "Work" && restored.symbolName == "briefcase")
        #expect(restored.colorHex == "#112233" && restored.sortOrder == 4 && restored.isSmart)
        #expect(restored.smartPredicateData == Data([1, 2, 3]) && restored.triggerBundleID == "com.apple.Notes")
        #expect(try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first?.collectionID == board.id)

        _ = try await service.redo()
        #expect(try ModelContext(container).fetch(FetchDescriptor<Pinboard>()).isEmpty)
    }

    @Test("a collection that a new one took the name of comes back under a numbered name")
    func whenTheNameIsTaken_thenTheRestoredCollectionIsNumbered() async throws {
        let board = Pinboard(name: "Work", symbolName: "folder", colorHex: "#111111", sortOrder: 0)
        container.mainContext.insert(board)
        try container.mainContext.save()
        try await service.deleteCollection(id: board.id)
        container.mainContext.insert(Pinboard(name: "Work", symbolName: "folder", colorHex: "#222222", sortOrder: 0))
        try container.mainContext.save()

        _ = try await service.undo()

        let names = try ModelContext(container).fetch(FetchDescriptor<Pinboard>()).map(\.name).sorted()
        #expect(names == ["Work", "Work 2"])
    }
}
