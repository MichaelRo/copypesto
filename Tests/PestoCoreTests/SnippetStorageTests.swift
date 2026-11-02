// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

/// A snippet used to be a row built by hand with the first 500 characters in the clear and no blob, so a
/// longer snippet pasted truncated and no backup held it.
@Suite("Snippets are stored like every other clip")
struct SnippetStorageTests {
    private let container: ModelContainer

    init() throws {
        container = try ModelContainerSetup.makeInMemory()
    }

    private func service() async -> StorageService {
        StorageService(modelContainer: container)
    }

    @Test("a snippet is pinned, keeps its whole text in an encrypted blob, and shows a sealed preview")
    func addSnippet_keepsTheWholeText() async throws {
        let text = String(repeating: "Dear customer, thank you for writing. ", count: 40)
        #expect(text.count > 500)

        let id = try #require(await service().addSnippet(text))

        let item = try #require(ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first { $0.id == id })
        #expect(item.isPinned)
        #expect(item.previewText.isEmpty, "the preview must be sealed, not stored in the clear")
        #expect(item.blob?.decryptedText() == text)
    }

    @Test("a snippet added with a name carries it as its title, and a clip that already has a title keeps its own")
    func addSnippet_carriesItsName() async throws {
        let service = await service()

        let named = try #require(await service.addSnippet("Meeting notes, {{date}}", title: "Meeting notes"))
        let again = try #require(await service.addSnippet("Meeting notes, {{date}}", title: "Another name"))

        let items = try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
        #expect(named == again)
        #expect(items.first { $0.id == named }?.customTitle == "Meeting notes")
    }

    @Test("a snippet is part of the backup")
    func addSnippet_isBackedUp() async throws {
        let service = await service()
        _ = try await service.addSnippet("Best regards,\nMichael")

        let export = try await service.backupRecords(includeSensitive: false)

        #expect(export.summary.items == 1)
        #expect(export.summary.skippedNoPayload == 0)
    }

    @Test("adding text the history already holds pins that clip instead of making a second one")
    func addSnippet_reusesAnExistingClip() async throws {
        let service = await service()
        let first = try await service.addSnippet("same words")
        let second = try await service.addSnippet("same words")

        #expect(first == second)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<ClipboardItem>()) == 1)
    }

    @Test("a snippet saved by an older version gets a blob from its preview, and is then backed up")
    func giveSnippetsABlob_backfillsOldSnippets() async throws {
        let context = ModelContext(container)
        let old = ClipboardItem(
            type: .text, previewText: "Kind regards", contentHash: "legacy", byteSize: 12,
            deviceID: "d", sequenceNumber: 1, isPinned: true
        )
        context.insert(old)
        try context.save()
        let service = await service()

        #expect(try await service.giveSnippetsABlob() == 1)
        #expect(try await service.giveSnippetsABlob() == 0, "running it again must change nothing")

        let item = try #require(ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first)
        #expect(item.blob?.decryptedText() == "Kind regards")
        #expect(item.previewText.isEmpty)
        #expect(try await service.backupRecords(includeSensitive: false).summary.items == 1)
    }

    private func item(_ id: UUID) throws -> ClipboardItem {
        try #require(ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first { $0.id == id })
    }

    @Test("editing a snippet replaces its text, title and preview, all sealed, and keeps it pinned")
    func updateSnippet_replacesTextAndTitle() async throws {
        let service = await service()
        let id = try #require(await service.addSnippet("Hi {{cursor}},\n\nThanks", title: "Thanks"))
        let before = try item(id).contentHash

        let changed = try await service.updateSnippet(
            id: id,
            title: "Thank you",
            text: "Dear {{cursor}},\n\nMany thanks"
        )

        #expect(changed)
        let edited = try item(id)
        #expect(edited.isPinned)
        #expect(edited.customTitle == "Thank you")
        #expect(edited.blob?.decryptedText() == "Dear {{cursor}},\n\nMany thanks")
        #expect(edited.displayPreviewText == "Dear {{cursor}},\n\nMany thanks")
        #expect(edited.previewText.isEmpty, "the preview must stay sealed")
        #expect(edited.textLength == "Dear {{cursor}},\n\nMany thanks".count)
        #expect(edited.contentHash != before)
    }

    @Test("an empty title removes the title; a long text keeps all of itself in the blob")
    func updateSnippet_clearsTheTitleAndKeepsLongText() async throws {
        let service = await service()
        let id = try #require(await service.addSnippet("short", title: "Name"))
        let long = String(repeating: "Dear customer, thank you. ", count: 60)

        try await service.updateSnippet(id: id, title: "  ", text: long)

        let edited = try item(id)
        #expect(edited.customTitle == nil)
        #expect(edited.blob?.decryptedText() == long)
        #expect(edited.displayPreviewText.count == 500)
    }

    @Test("an edit that turns the text into a secret is masked like a copy would be")
    func updateSnippet_secretIsMasked() async throws {
        let service = await service()
        let id = try #require(await service.addSnippet("harmless"))

        try await service.updateSnippet(id: id, title: nil, text: "4111 1111 1111 1111")

        let edited = try item(id)
        #expect(edited.sensitivity == .creditCard)
        #expect(!edited.previewText.contains("4111"))
        #expect(edited.blob?.decryptedText() == "4111 1111 1111 1111")
    }

    @Test("editing a clip that is not there, or to nothing, changes nothing")
    func updateSnippet_missingOrEmpty() async throws {
        let service = await service()
        let id = try #require(await service.addSnippet("keep me"))

        #expect(try await service.updateSnippet(id: UUID(), title: nil, text: "x") == false)
        #expect(try await service.updateSnippet(id: id, title: nil, text: "   ") == false)
        #expect(try item(id).blob?.decryptedText() == "keep me")
    }

    @Test(
        "saving or editing a snippet in the plain-text builder clears stale rich-text formatting from an earlier copy"
    )
    func snippetBuilder_clearsStaleRichPayload() async throws {
        let service = await service()
        let text = "Hello {{input:Name}}"
        let payload = Data(text.utf8)
        let rich = RichTextPayload(rtf: Data("{\\rtf1\\ansi Hello}".utf8))
        try await service.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text",
            payload: payload,
            payloadString: text,
            contentHash: payload.sha256Hex,
            richPayload: rich
        ))
        let copied = try #require(ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first)
        #expect(copied.blob?.decryptedRichPayload() == rich)

        let addedID = try #require(await service.addSnippet(text, title: "Greeting"))
        #expect(addedID == copied.id)
        #expect(try item(addedID).blob?.decryptedRichPayload() == nil)

        try await service.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text",
            payload: Data("Other".utf8),
            payloadString: "Other",
            contentHash: Data("Other".utf8).sha256Hex,
            richPayload: rich
        ))
        let other = try #require(ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first {
            $0.id != addedID
        })
        #expect(other.blob?.decryptedRichPayload() == rich)

        try await service.updateSnippet(id: other.id, title: "Updated", text: "Updated {{date}}")
        #expect(try item(other.id).blob?.decryptedRichPayload() == nil)
    }

    @Test(
        "adding a snippet with placeholders creates the Snippets smart collection, and deleting the last removes it"
    )
    func snippetsCollection_autoCreatedWhenSnippetExistsAndRemovedWhenLastSnippetDeleted() async throws {
        let service = await service()
        let firstID = try #require(await service.addSnippet("Hello {{input:Name}}", title: "Greeting"))

        var boards = try ModelContext(container).fetch(FetchDescriptor<Pinboard>())
        #expect(boards.count == 1)
        let snippetsBoard = try #require(boards.first)
        #expect(snippetsBoard.id == CollectionSuggester.snippetsCollectionID)
        #expect(snippetsBoard.name == "Snippets")
        #expect(snippetsBoard.symbolName == "curlybraces")
        #expect(snippetsBoard.isSmart)
        let ruleSet = try #require(snippetsBoard.smartPredicateData.flatMap {
            try? SmartCollectionPredicate.decodeRuleSet($0)
        })
        #expect(ruleSet == CollectionSuggester.snippetsRuleSet)
        #expect(try ruleSet.matches(item(firstID)))

        try await service.deleteItems(ids: [firstID], reason: .user)
        boards = try ModelContext(container).fetch(FetchDescriptor<Pinboard>())
        #expect(boards.isEmpty, "the unmodified Snippets collection should go away when no snippets remain")

        let secondID = try #require(await service.addSnippet("Thanks {{date}}", title: "Thanks"))
        boards = try ModelContext(container).fetch(FetchDescriptor<Pinboard>())
        #expect(boards.count == 1, "adding a snippet again should bring the Snippets collection back")
        #expect(try ruleSet.matches(item(secondID)))
    }

    @Test(
        "deleting the Snippets collection keeps it deleted when new snippets are added, and Undo brings it back"
    )
    func snippetsCollection_userDeleteSuppressesAutoCreationUntilUndone() async throws {
        let undoHistory = UndoHistory()
        let service = StorageService(modelContainer: container, environment: .testing {
            $0.undoHistory = undoHistory
        })
        _ = try #require(await service.addSnippet("First {{date}}", title: "First"))
        let boardID = try #require(ModelContext(container).fetch(FetchDescriptor<Pinboard>()).first?.id)

        #expect(try await service.deleteCollection(id: boardID))
        #expect(try ModelContext(container).fetch(FetchDescriptor<Pinboard>()).isEmpty)

        _ = try #require(await service.addSnippet("Second {{input:Name}}", title: "Second"))
        #expect(
            try ModelContext(container).fetch(FetchDescriptor<Pinboard>()).isEmpty,
            "explicitly deleting the Snippets collection must not recreate it behind the user's back"
        )

        _ = try await service.undo() // undoes adding "Second"
        _ = try await service.undo() // undoes deleting "Snippets" collection
        #expect(
            try ModelContext(container).fetch(FetchDescriptor<Pinboard>()).map(\.name) == ["Snippets"],
            "undoing the collection deletion should restore the Snippets collection"
        )
    }

    @Test("reordering or renaming the Snippets collection is preserved when more snippets are added")
    func snippetsCollection_preservesUserReorderingAndCustomization() async throws {
        let service = await service()
        _ = try #require(await service.addSnippet("One {{date}}", title: "One"))

        let context = ModelContext(container)
        let snippetsBoard = try #require(context.fetch(FetchDescriptor<Pinboard>()).first)
        snippetsBoard.sortOrder = 5
        snippetsBoard.name = "My Templates"
        try context.save()

        _ = try #require(await service.addSnippet("Two {{time}}", title: "Two"))

        let boards = try ModelContext(container).fetch(FetchDescriptor<Pinboard>())
        #expect(boards.count == 1)
        #expect(boards.first?.name == "My Templates")
        #expect(boards.first?.sortOrder == 5)
    }

    @Test("editing a snippet updates HistoryStore's search index immediately")
    @MainActor
    func updateSnippet_refreshesHistoryStoreSearchIndexImmediately() async throws {
        let store = HistoryStore(container: container)
        store.setVisible(true)
        store.refresh()

        let service = StorageService(modelContainer: container)
        let id = try #require(await service.addSnippet("Initial {{input:Client}} body", title: "AlphaTitle"))
        try await store.waitForRefresh()

        var index = try #require(store.searchIndex())
        #expect(index.matching(HistoryCriteria(query: "alphatitle")) == [id])
        #expect(index.matching(HistoryCriteria(query: "snippet")) == [id])
        #expect(index.matching(HistoryCriteria(query: "@snippet")) == [id])

        try await service.updateSnippet(id: id, title: "OmegaTitle", text: "Revised {{input:Partner}} text")
        try await store.waitForRefresh()

        index = try #require(store.searchIndex())
        #expect(index.matching(HistoryCriteria(query: "omegatitle")) == [id])
        #expect(index.matching(HistoryCriteria(query: "revised")) == [id])
        #expect(index.matching(HistoryCriteria(query: "alphatitle")).isEmpty)
    }
}
