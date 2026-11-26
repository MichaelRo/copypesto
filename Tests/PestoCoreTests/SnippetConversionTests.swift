// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("A text clip becomes a snippet in place, and one Undo takes it back", .serialized)
@MainActor
struct SnippetConversionTests {
    private let container: ModelContainer
    private let service: StorageService
    private let history = UndoHistory()

    init() throws {
        container = try ModelContainerSetup.makeInMemory()
        service = StorageService(modelContainer: container, environment: .testing { [history] in
            $0.undoHistory = history
        })
    }

    @discardableResult
    private func ingest(_ text: String, type: String = "public.utf8-plain-text") async throws -> UUID {
        let hash = Data(SHA256.hash(data: Data(text.utf8))).hexString
        try await service.ingest(PasteboardCapture(
            typeIdentifier: type, payload: Data(text.utf8), payloadString: text,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000), contentHash: hash
        ))
        await service.waitForBackgroundWork()
        return try #require(clips().first { $0.blob?.decryptedText() == text }).id
    }

    private func clips() throws -> [ClipboardItem] {
        try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
    }

    private func clip(_ id: UUID) throws -> ClipboardItem {
        try #require(clips().first { $0.id == id })
    }

    private func boards() throws -> [Pinboard] {
        try ModelContext(container).fetch(FetchDescriptor<Pinboard>())
    }

    @Test("the same clip is pinned with the new text, keeps its note, tags and collection, and Snippets appears")
    func whenConverted_thenTheSameClipIsASnippet() async throws {
        let id = try await ingest("Hello Anna, thanks for the order")
        let collection = UUID()
        let context = ModelContext(container)
        let item = try #require(context.fetch(FetchDescriptor<ClipboardItem>()).first { $0.id == id })
        item.userNote = "Note"
        item.tags = ["reply"]
        item.collectionID = collection
        try context.saveOrRollback()

        let outcome = try await service.convertToSnippet(
            id: id, title: "Order reply", text: "Hello {{input:name}}, thanks for the order"
        )

        #expect(outcome == .converted)
        let after = try clip(id)
        #expect(try clips().count == 1, "converting must not leave the original beside a copy")
        #expect(after.isPinned)
        #expect(after.isTemplate)
        #expect(after.blob?.decryptedText() == "Hello {{input:name}}, thanks for the order")
        #expect(after.customTitle == "Order reply")
        #expect(after.userNote == "Note")
        #expect(after.tags == ["reply"])
        #expect(after.collectionID == collection)
        #expect(after.previewText.isEmpty, "the preview stays sealed")
        #expect(try boards().contains { $0.id == PredicateRuleSet.snippetsCollectionID })
        #expect(history.undoLabel == .makeSnippet)
    }

    @Test("one Undo puts the old text back and unpins the clip; Redo makes it a snippet again")
    func whenConversionUndone_thenTheClipIsAsItWas() async throws {
        let id = try await ingest("Dear team, the build is green")
        let hashBefore = try clip(id).contentHash
        _ = try await service.convertToSnippet(id: id, title: nil, text: "Dear {{input:who}}, the build is green")

        try await service.undo()

        var restored = try clip(id)
        #expect(!restored.isPinned)
        #expect(!restored.isTemplate)
        #expect(restored.contentHash == hashBefore)
        #expect(restored.blob?.decryptedText() == "Dear team, the build is green")
        #expect(try !boards().contains { $0.id == PredicateRuleSet.snippetsCollectionID })

        try await service.redo()

        restored = try clip(id)
        #expect(restored.isPinned)
        #expect(restored.isTemplate)
        #expect(try boards().contains { $0.id == PredicateRuleSet.snippetsCollectionID })
    }

    @Test("text without a placeholder is refused, so a pinned clip is never called a snippet")
    func whenTextHasNoPlaceholder_thenNothingChanges() async throws {
        let id = try await ingest("plain words")
        let mark = history.recordedCount

        let outcome = try await service.convertToSnippet(id: id, title: nil, text: "plain words, edited")

        #expect(outcome == .needsPlaceholder)
        #expect(try !clip(id).isPinned)
        #expect(try clip(id).blob?.decryptedText() == "plain words")
        #expect(history.recordedCount == mark)
    }

    @Test("a secret is never made a snippet")
    func whenClipIsASecret_thenItIsRefused() async throws {
        let id = try await ingest("sk-ant-api03-EXAMPLEEXAMPLEEXAMPLEEXAMPLE1234567890abcdef")
        #expect(try clip(id).sensitivityRaw != nil)

        let outcome = try await service.convertToSnippet(id: id, title: nil, text: "key {{input:name}}")

        #expect(outcome == .notConvertible)
        #expect(try !clip(id).isPinned)
    }

    @Test("a clip that is gone is reported, not created")
    func whenClipIsMissing_thenItIsReported() async throws {
        let outcome = try await service.convertToSnippet(id: UUID(), title: nil, text: "x {{date}}")

        #expect(outcome == .missing)
        #expect(try clips().isEmpty)
    }

    @Test("a text over the size limit throws the limit's message and changes nothing")
    func whenTextIsTooLarge_thenItThrows() async throws {
        let id = try await ingest("short {{date}}")
        let huge = String(repeating: "a", count: ClipSizePolicy.maxTextBytes + 1) + "{{date}}"

        await #expect(throws: ClipSizePolicy.TooLarge.self) {
            try await service.convertToSnippet(id: id, title: nil, text: huge)
        }
        #expect(try !clip(id).isPinned)
    }
}
