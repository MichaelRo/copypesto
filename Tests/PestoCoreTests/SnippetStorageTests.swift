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
}
