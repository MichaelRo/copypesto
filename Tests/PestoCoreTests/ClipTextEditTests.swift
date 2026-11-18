// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

private struct EchoEmbedder: TextEmbedding {
    func embed(text: String) async -> Data? {
        Data("vector:\(text)".utf8)
    }
}

@Suite("A text clip's content can be edited, sealed and undone like any change", .serialized)
@MainActor
struct ClipTextEditTests {
    private let container: ModelContainer
    private let service: StorageService
    private let history = UndoHistory()

    init() throws {
        container = try ModelContainerSetup.makeInMemory()
        service = StorageService(modelContainer: container, environment: .testing { [history] in
            $0.undoHistory = history
            $0.embedder = EchoEmbedder()
        })
    }

    private func sha(_ text: String) -> String {
        Data(SHA256.hash(data: Data(text.utf8))).hexString
    }

    @discardableResult
    private func ingest(_ text: String, at offset: TimeInterval = 0) async throws -> UUID {
        try await service.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000 + offset), contentHash: sha(text)
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

    @Test("the new text is sealed under the clip's own id, with a new content hash and a sealed preview")
    func whenTextEdited_thenBlobIsResealedWithANewHash() async throws {
        let id = try await ingest("first draft of the note")
        let oldHash = try clip(id).contentHash

        let outcome = try await service.updateText(id: id, text: "second draft of the note")

        #expect(outcome == .saved)
        let edited = try clip(id)
        let blob = try #require(edited.blob)
        #expect(blob.aadBound)
        let opened = try BlobEncryption().decrypt(
            .init(ciphertext: blob.encryptedData, nonce: blob.nonceData),
            associatedData: BlobEncryption.associatedData(itemID: id, field: .blob)
        )
        #expect(String(data: opened, encoding: .utf8) == "second draft of the note")
        #expect(edited.contentHash != oldHash)
        #expect(edited.contentHash == ContentHash.stored(
            sha("second draft of the note"),
            key: try? BlobEncryption()
                .loadOrCreateKey()
        ))
        #expect(edited.previewText.isEmpty)
        #expect(edited.previewAADBound)
        #expect(edited.displayPreviewText == "second draft of the note")
        #expect(edited.byteSize == "second draft of the note".utf8.count)
        #expect(edited.textLength == "second draft of the note".count)
    }

    @Test("editing a clip to the text another clip holds saves it, keeps both clips, and Undo restores the old text")
    func whenEditedToAnotherClipsText_thenBothClipsStayAndUndoRestores() async throws {
        let first = try await ingest("alpha text", at: 0)
        let second = try await ingest("beta text", at: 10)

        let outcome = try await service.updateText(id: first, text: "beta text")

        #expect(outcome == .saved)
        #expect(try clips().count == 2)
        #expect(try clip(first).blob?.decryptedText() == "beta text")
        #expect(try clip(second).blob?.decryptedText() == "beta text")
        #expect(try clip(first).contentHash == clip(second).contentHash)
        #expect(history.undoLabel == .editText)

        try await service.undo()
        #expect(try clip(first).blob?.decryptedText() == "alpha text")
        #expect(try clip(second).blob?.decryptedText() == "beta text")
    }

    @Test("Undo and Redo apply even when another clip holds the text they go back to")
    func whenTargetTextHeldByAnother_thenUndoAndRedoStillApply() async throws {
        let first = try await ingest("alpha text", at: 0)
        let second = try await ingest("beta text", at: 10)
        try await service.updateText(id: first, text: "gamma text")
        try await service.updateText(id: second, text: "alpha text")
        try await service.undo()
        try await service.undo()
        #expect(try clip(first).blob?.decryptedText() == "alpha text")

        try await service.redo()
        #expect(try clip(first).blob?.decryptedText() == "gamma text")
        try await service.updateText(id: first, text: "beta text")
        try await service.undo()
        try await service.redo()
        #expect(try clip(first).blob?.decryptedText() == "beta text")
        #expect(try clip(second).blob?.decryptedText() == "beta text")
    }

    @Test("an edit to a text another clip holds gets its own search vector")
    func whenEditedToAnotherClipsText_thenItGetsItsOwnVector() async throws {
        let first = try await ingest("alpha text for the vector", at: 0)
        let second = try await ingest("beta text for the vector", at: 10)
        let vectorOfSecond = try clip(second).embeddingData

        try await service.updateText(id: first, text: "beta text for the vector")
        await service.waitForBackgroundWork()

        #expect(try clip(first).embeddingData == Data("vector:beta text for the vector".utf8))
        #expect(try clip(second).embeddingData == vectorOfSecond)
    }

    @Test("the same text again changes nothing and records nothing")
    func whenTextUnchanged_thenNothingIsRecorded() async throws {
        let id = try await ingest("steady text")
        #expect(try await service.updateText(id: id, text: "steady text") == .unchanged)
        #expect(history.undoLabel == nil)
    }

    @Test("adding a card number masks the clip and its preview; removing it unmasks the clip")
    func whenSecretAddedOrRemoved_thenMaskFollows() async throws {
        let id = try await ingest("harmless words")

        try await service.updateText(id: id, text: "4111 1111 1111 1111")
        var edited = try clip(id)
        #expect(edited.sensitivity == .creditCard)
        #expect(edited.previewCiphertext == nil)
        #expect(!edited.previewText.contains("4111"))
        #expect(edited.sensitivityMaskedPreview?.contains("4111") == false)
        #expect(edited.embeddingData == nil)

        try await service.updateText(id: id, text: "harmless words again")
        edited = try clip(id)
        #expect(edited.sensitivityRaw == nil)
        #expect(edited.sensitivityMaskedPreview == nil)
        #expect(edited.previewText.isEmpty)
        #expect(edited.displayPreviewText == "harmless words again")
    }

    @Test("the kind and language are read again: a link, a color and code")
    func whenTextEdited_thenKindIsReadAgain() async throws {
        let id = try await ingest("plain words here")

        try await service.updateText(id: id, text: "https://copypesto.net/guide")
        #expect(try clip(id).type == .url)

        try await service.updateText(id: id, text: "#3A7BD5")
        let color = try clip(id)
        #expect(color.type == .color)
        #expect(color.previewText == "#3A7BD5", "a color's preview is the one kept in the clear")

        try await service.updateText(id: id, text: "{\"name\": \"Pesto\", \"items\": [1, 2, 3]}")
        let code = try clip(id)
        #expect(code.type == .code)
        #expect(code.detectedLanguage == JSONText.language)

        try await service.updateText(id: id, text: "plain words once more")
        let text = try clip(id)
        #expect(text.type == .text)
        #expect(text.detectedLanguage == nil)
        #expect(text.previewText.isEmpty)
    }

    @Test("an explicit link is marked, and the mark goes when the text is edited to something that is not")
    func whenExplicitLinkEditedAway_thenTheMarkIsCleared() async throws {
        let id = try await ingest("plain words here")

        try await service.updateText(id: id, text: "https://pornhub.com/video/123")
        #expect(try clip(id).isNSFW)

        try await service.updateText(id: id, text: "https://copypesto.net/guide")
        #expect(try clip(id).isNSFW == false)

        try await service.updateText(id: id, text: "https://pornhub.com/video/456")
        try await service.updateText(id: id, text: "plain words once more")
        #expect(try clip(id).isNSFW == false)
    }

    @Test("the search vector and the text signature follow the new text")
    func whenTextEdited_thenVectorAndSignatureAreRefreshed() async throws {
        let old = "The quarterly report is due on Friday, please send your numbers early."
        let new = "Lunch is moved to the large room on the second floor at half past twelve."
        let id = try await ingest(old)
        let before = try clip(id)
        #expect(before.embeddingData == Data("vector:\(SemanticIndexer.embeddingInput(for: old))".utf8))
        let oldSignature = try #require(before.metadata.signature)

        try await service.updateText(id: id, text: new)
        await service.waitForBackgroundWork()

        let after = try clip(id)
        #expect(after.embeddingData == Data("vector:\(SemanticIndexer.embeddingInput(for: new))".utf8))
        let newSignature = try #require(after.metadata.signature)
        #expect(newSignature != oldSignature)

        try await service.updateText(id: id, text: "short")
        await service.waitForBackgroundWork()
        #expect(try clip(id).metadata.signature == nil)
        #expect(try clip(id).embeddingData == nil)
    }

    @Test("title, note, tags, collection, pin, first copy and place in the history stay as they were")
    func whenTextEdited_thenCurationAndOrderStay() async throws {
        let id = try await ingest("keep my place")
        let collection = UUID()
        let context = ModelContext(container)
        let item = try #require(context.fetch(FetchDescriptor<ClipboardItem>()).first { $0.id == id })
        item.customTitle = "Title"
        item.userNote = "Note"
        item.tags = ["one", "two"]
        item.collectionID = collection
        item.isPinned = true
        item.collectionOrder = 3
        item.bringToFront(at: Date(timeIntervalSince1970: 1_800_000_100))
        try context.saveOrRollback()
        let before = try clip(id)
        let timestamp = before.timestamp
        let copiedAt = before.metadata.copiedAt
        let sequence = before.sequenceNumber

        try await service.updateText(id: id, text: "keep my place, edited")

        let after = try clip(id)
        #expect(after.customTitle == "Title")
        #expect(after.userNote == "Note")
        #expect(after.tags == ["one", "two"])
        #expect(after.collectionID == collection)
        #expect(after.isPinned)
        #expect(after.collectionOrder == 3)
        #expect(after.timestamp == timestamp)
        #expect(after.metadata.copiedAt == copiedAt)
        #expect(after.sequenceNumber == sequence)
    }

    @Test("one Undo restores the old content byte for byte, and Redo the new")
    func whenTextEdited_thenOneUndoRestoresTheOldBytes() async throws {
        let id = try await ingest("original words")
        let original = try clip(id)
        let sealedBefore = try #require(original.blob?.encryptedData)
        let hashBefore = original.contentHash
        let previewBefore = original.previewCiphertext
        let mark = history.recordedCount

        try await service.updateText(id: id, text: "rewritten words")

        #expect(history.recordedCount == mark + 1)
        #expect(history.undoLabel == .editText)
        try await service.undo()
        let undone = try clip(id)
        #expect(undone.blob?.encryptedData == sealedBefore)
        #expect(undone.contentHash == hashBefore)
        #expect(undone.previewCiphertext == previewBefore)
        #expect(undone.blob?.decryptedText() == "original words")
        #expect(undone.displayPreviewText == "original words")

        try await service.redo()
        #expect(try clip(id).blob?.decryptedText() == "rewritten words")
    }

    @Test("an edit drops the formatted copy so a paste matches the card, and Undo brings it back with the old text")
    func whenFormattedClipEdited_thenRichPayloadIsDroppedAndUndoRestoresIt() async throws {
        let text = "Formatted heading"
        let rich = RichTextPayload(rtf: Data("{\\rtf1\\ansi \\b Formatted heading}".utf8))
        try await service.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
            contentHash: sha(text), richPayload: rich
        ))
        await service.waitForBackgroundWork()
        let id = try #require(clips().first { $0.blob?.decryptedText() == text }).id
        #expect(try clip(id).blob?.decryptedRichPayload() == rich)

        #expect(try await service.updateText(id: id, text: "Plain heading") == .saved)

        let edited = try clip(id)
        #expect(edited.blob?.decryptedRichPayload() == nil)
        #expect(edited.blob?.encryptedRichData == nil)
        #expect(edited.blob?.decryptedText() == "Plain heading")

        try await service.undo()
        let undone = try clip(id)
        #expect(undone.blob?.decryptedText() == text)
        #expect(undone.blob?.decryptedRichPayload() == rich)
    }

    @Test("a clip that expires on its own is edited but never held by Undo")
    func whenClipExpires_thenTheEditIsNotUndoable() async throws {
        let id = try await ingest("burn after reading")
        let context = ModelContext(container)
        let item = try #require(context.fetch(FetchDescriptor<ClipboardItem>()).first { $0.id == id })
        item.expiresAt = Date(timeIntervalSince1970: 1_900_000_000)
        try context.saveOrRollback()

        #expect(try await service.updateText(id: id, text: "burn after reading twice") == .saved)
        #expect(history.undoLabel == nil)
    }

    @Test("an empty text, a missing clip and a picture are refused")
    func whenNothingToEdit_thenRefused() async throws {
        let id = try await ingest("still here")
        #expect(try await service.updateText(id: id, text: "  \n ") == .empty)
        #expect(try await service.updateText(id: UUID(), text: "anything") == .missing)
        #expect(try clip(id).blob?.decryptedText() == "still here")

        try await service.ingest(PasteboardCapture(
            typeIdentifier: "public.png", payload: Data("not really a png".utf8), payloadString: nil,
            contentHash: sha("png")
        ))
        await service.waitForBackgroundWork()
        let picture = try #require(clips().first { $0.type == .image })
        #expect(try await service.updateText(id: picture.id, text: "words") == .notText)
    }

    @Test("a text over the size limit is refused with the copy's message")
    func whenTextTooLarge_thenThrows() async throws {
        let id = try await ingest("small")
        let huge = String(repeating: "a", count: ClipSizePolicy.maxTextBytes + 1)
        await #expect(throws: ClipSizePolicy.TooLarge.self) {
            try await service.updateText(id: id, text: huge)
        }
        #expect(try clip(id).blob?.decryptedText() == "small")
    }

    @Test("a snippet edited through the general path stays a snippet edit")
    func whenSnippetEdited_thenItsLabelStays() async throws {
        let id = try #require(try await service.addSnippet("Dear {{name}}", title: "Greeting"))
        try await service.updateSnippet(id: id, title: "Greeting", text: "Hello {{name}}")
        #expect(history.undoLabel == .editSnippet)
    }
}

@Suite("An edited clip's text reaches the store only sealed")
struct ClipTextEditOnDiskTests {
    @Test("the new text appears in none of the files the store writes")
    func whenTextEdited_thenNoPlaintextOnDisk() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-edit-ondisk-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try ModelContainer(
            for: ClipboardItem.self, ClipboardBlob.self, DeletedItemTombstone.self, Pinboard.self,
            configurations: ModelConfiguration(
                "clips", url: directory.appendingPathComponent("clips.store"), cloudKitDatabase: .none
            )
        )
        let service = StorageService(modelContainer: container, environment: .testing())
        let original = "meeting notes \(UUID().uuidString)"
        let edited = "edited meeting notes \(UUID().uuidString)"
        try await service.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data(original.utf8), payloadString: original,
            contentHash: Data(SHA256.hash(data: Data(original.utf8))).hexString
        ))
        let id = try #require(ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first?.id)

        #expect(try await service.updateText(id: id, text: edited) == .saved)

        let enumerator = try #require(FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey]
        ))
        var scanned = 0
        for url in enumerator.allObjects.compactMap({ $0 as? URL }) {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let data = try Data(contentsOf: url)
            scanned += 1
            #expect(data.range(of: Data(edited.utf8)) == nil, "\(url.lastPathComponent) holds the edited text")
        }
        #expect(scanned > 0)
    }
}
