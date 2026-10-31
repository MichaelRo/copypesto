// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("Every kind of change can be undone and redone", .serialized)
@MainActor
struct EveryActionUndoTests {
    private let container: ModelContainer
    private let service: StorageService
    private let history = UndoHistory()

    init() async throws {
        container = try ModelContainerSetup.makeInMemory()
        service = StorageService(modelContainer: container, environment: .testing { [history] in
            $0.undoHistory = history
        })
    }

    private var store: CollectionStore {
        CollectionStore(context: container.mainContext, undoHistory: history)
    }

    private func editor() -> ClipEditor {
        ClipEditor(
            context: container.mainContext, historyStore: nil, report: { _, work in try? work() }, didEdit: {},
            undoHistory: history
        )
    }

    private func boards() throws -> [Pinboard] {
        try ModelContext(container).fetch(FetchDescriptor<Pinboard>(sortBy: [SortDescriptor(\.sortOrder)]))
    }

    private func clips() throws -> [ClipboardItem] {
        try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp)]))
    }

    private func tombstones() throws -> Int {
        try ModelContext(container).fetch(FetchDescriptor<DeletedItemTombstone>()).count
    }

    private func ingest(_ text: String, at offset: TimeInterval = 0, realHash: Bool = false) async throws {
        try await service.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
            timestamp: .now.addingTimeInterval(offset),
            contentHash: realHash ? Data(text.utf8).sha256Hex : "hash-\(text)"
        ))
    }

    private func board(_ name: String, order: Int) -> Pinboard {
        Pinboard(name: name, symbolName: "folder", colorHex: "#112233", sortOrder: order)
    }

    // MARK: Collections

    @Test("a new collection is taken back and added again")
    func whenCollectionCreated_thenUndoRemovesAndRedoRestores() async throws {
        let created = board("Work", order: 0)
        try store.insert(.create, [created])
        #expect(history.undoLabel == .createCollection("Work"))

        #expect(try await service.undo()?.label == .createCollection("Work"))
        #expect(try boards().isEmpty)

        #expect(try await service.redo()?.direction == .redone)
        #expect(try boards().map(\.name) == ["Work"])
        #expect(try boards().first?.id == created.id)
    }

    @Test("renaming, recoloring and changing a collection's rule go back together")
    func whenCollectionEdited_thenUndoRestoresEveryField() async throws {
        let work = board("Work", order: 0)
        try store.insert(.create, [work])
        try store.edit(.edit, [work]) {
            work.name = "Office"
            work.colorHex = "#FFFFFF"
            work.isSmart = true
            work.smartPredicateData = Data([9, 9])
        }
        #expect(history.undoLabel == .editCollection("Office"))

        try await service.undo()
        let back = try #require(boards().first)
        #expect(back.name == "Work")
        #expect(back.colorHex == "#112233")
        #expect(back.isSmart == false)
        #expect(back.smartPredicateData == nil)

        try await service.redo()
        #expect(try boards().first?.name == "Office")
    }

    @Test("an edit that changes nothing records nothing")
    func whenCollectionUnchanged_thenNothingIsKept() throws {
        let work = board("Work", order: 0)
        try store.insert(.create, [work])
        let before = history.recordedCount
        try store.edit(.edit, [work]) {}
        #expect(history.recordedCount == before)
    }

    @Test("reordering collections is one action")
    func whenCollectionsReordered_thenOneUndoRestoresTheOrder() async throws {
        let first = board("A", order: 0)
        let second = board("B", order: 1)
        let third = board("C", order: 2)
        try store.insert(.create, [first, second, third])
        try store.edit(.reorder, [first, second, third]) {
            third.sortOrder = 0
            first.sortOrder = 1
            second.sortOrder = 2
        }
        #expect(history.undoLabel == .reorderCollections)
        #expect(try boards().map(\.name) == ["C", "A", "B"])

        try await service.undo()
        #expect(try boards().map(\.name) == ["A", "B", "C"])
        try await service.redo()
        #expect(try boards().map(\.name) == ["C", "A", "B"])
    }

    @Test("a duplicate is taken back and made again")
    func whenDuplicated_thenUndoRemovesTheCopy() async throws {
        let original = board("Work", order: 0)
        try store.insert(.create, [original])
        let copy = board("Work copy", order: 1)
        try store.insert(.duplicate, [copy])
        #expect(history.undoLabel == .duplicateCollection("Work copy"))

        try await service.undo()
        #expect(try boards().map(\.name) == ["Work"])
        try await service.redo()
        #expect(try boards().map(\.name) == ["Work", "Work copy"])
    }

    // MARK: Clip order and drag to a collection

    @Test("dragging a card to a new place in a collection is undone for every card that moved")
    func whenCardsReordered_thenUndoRestoresTheOrder() async throws {
        try await ingest("a", at: 0)
        try await ingest("b", at: 1)
        try await ingest("c", at: 2)
        let items = try container.mainContext.fetch(
            FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp)])
        )
        let order = Dictionary(uniqueKeysWithValues: zip(items.map(\.id), [2, 0, 1]))

        editor().edit(items) { $0.collectionOrder = order[$0.id] }
        #expect(history.undoLabel == .changeClip(.order))
        #expect(try clips().map(\.collectionOrder) == [2, 0, 1])

        try await service.undo()
        #expect(try clips().map(\.collectionOrder) == [nil, nil, nil])
        try await service.redo()
        #expect(try clips().map(\.collectionOrder) == [2, 0, 1])
    }

    // MARK: Additions

    @Test("a new snippet is taken back without a tombstone, and added again with the same id")
    func whenSnippetAdded_thenUndoRemovesItAndRedoRestoresIt() async throws {
        let id = try #require(try await service.addSnippet("Hello {{name}}", title: "Greeting"))
        #expect(history.undoLabel == .addClips(.snippet, 1))

        #expect(try await service.undo()?.direction == .undone)
        #expect(try clips().isEmpty)
        #expect(try tombstones() == 0)

        #expect(try await service.redo()?.direction == .redone)
        let back = try #require(clips().first)
        #expect(back.id == id)
        #expect(back.isPinned)
        #expect(back.customTitle == "Greeting")
        #expect(back.displayPreviewText == "Hello {{name}}")
    }

    @Test("pinning text the history already holds is an edit, not an addition")
    func whenTextAlreadyThere_thenSnippetIsAPinChange() async throws {
        try await ingest("Hello {{name}}", realHash: true)
        let before = history.recordedCount
        try await service.addSnippet("Hello {{name}}")
        #expect(history.recordedCount == before + 1)
        #expect(history.undoLabel == .changeClip(.pinned))

        try await service.undo()
        #expect(try clips().first?.isPinned == false)
        #expect(try clips().count == 1)
    }

    @Test("a batch of snippets is one action")
    func whenSnippetsImported_thenOneUndoTakesThemAllBack() async throws {
        let kept = await service.addSnippets([("one {{a}}", "One"), ("two {{b}}", nil), ("three {{c}}", "Three")])
        #expect(kept == 3)
        #expect(history.undoLabel == .addClips(.snippet, 3))

        try await service.undo()
        #expect(try clips().isEmpty)
        try await service.redo()
        #expect(try clips().count == 3)
    }

    @Test("editing a snippet's text is undone to the old text, and redone to the new")
    func whenSnippetEdited_thenTheTextGoesBackAndForth() async throws {
        let id = try #require(try await service.addSnippet("old {{x}}", title: "Old"))
        try await service.updateSnippet(id: id, title: "New", text: "new {{y}} text")
        #expect(history.undoLabel == .editSnippet)

        try await service.undo()
        var snippet = try #require(clips().first)
        #expect(snippet.displayPreviewText == "old {{x}}")
        #expect(snippet.customTitle == "Old")
        #expect(snippet.isPinned)

        try await service.redo()
        snippet = try #require(clips().first)
        #expect(snippet.displayPreviewText == "new {{y}} text")
        #expect(snippet.customTitle == "New")
    }

    @Test("an imported collection takes its clips and its collection back together")
    func whenCollectionImported_thenUndoRemovesBoth() async throws {
        let source = try ModelContainerSetup.makeInMemory()
        let sourceService = StorageService(modelContainer: source, environment: .testing())
        try await sourceService.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data("shared".utf8), payloadString: "shared",
            timestamp: .now, contentHash: "hash-shared"
        ))
        let sourceContext = ModelContext(source)
        let shared = Pinboard(name: "Shared", symbolName: "folder", colorHex: "#112233", sortOrder: 0)
        sourceContext.insert(shared)
        try sourceContext.fetch(FetchDescriptor<ClipboardItem>()).forEach { $0.collectionID = shared.id }
        try sourceContext.save()
        let file = try await HistoryExporter(modelContainer: source).exportCollection(id: shared.id)

        try await HistoryExporter(modelContainer: container).importCollection(from: file, undoHistory: history)
        #expect(history.undoLabel == .importCollection("Shared"))
        #expect(try boards().count == 1)
        #expect(try clips().count == 1)

        try await service.undo()
        #expect(try boards().isEmpty)
        #expect(try clips().isEmpty)
        #expect(try tombstones() == 0)

        try await service.redo()
        #expect(try boards().map(\.name) == ["Shared"])
        #expect(try clips().first?.collectionID == shared.id)
    }

    // MARK: Policy and wipe

    @Test("the confirmation asks the policy whether a delete can be undone")
    func whenJudgedTogether_thenOneClipThatCannotBeHeldDecides() async throws {
        try await ingest("small")
        let items = try container.mainContext.fetch(FetchDescriptor<ClipboardItem>())
        #expect(UndoPolicy.canHold(items))
        #expect(!UndoPolicy.canHold([]))
        items.first?.expiresAt = .now.addingTimeInterval(60)
        #expect(!UndoPolicy.canHold(items))
    }

    @Test("clearing history forgets collection changes and additions too")
    func whenCleared_thenNoKindSurvives() async throws {
        try store.insert(.create, [board("Work", order: 0)])
        try await service.addSnippet("keep {{x}}")
        #expect(history.entryCount == 2)
        try await service.clearNonPinned(in: .all)
        #expect(history.entryCount == 0)
    }
}
