// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("Clips stored wrong are repaired once")
struct StorageRepairTests {
    private let container: ModelContainer

    init() throws {
        container = try ModelContainerSetup.makeInMemory().synced
    }

    private func insertColorClip(_ text: String) throws -> UUID {
        let context = ModelContext(container)
        let item = ClipboardItem(
            type: .color, previewText: text, contentHash: UUID().uuidString, byteSize: text.utf8.count,
            deviceID: "test", sequenceNumber: 1
        )
        let envelope = try BlobEncryption().encrypt(
            Data(text.utf8), associatedData: BlobEncryption.associatedData(itemID: item.id, field: .blob)
        )
        let blob = ClipboardBlob(
            encryptedData: envelope.ciphertext, nonceData: envelope.nonce, mimeType: "public.utf8-plain-text"
        )
        blob.aadBound = true
        item.blob = blob
        context.insert(item)
        context.insert(blob)
        try context.save()
        return item.id
    }

    private func insertEmptyRichTextClip(_ rtf: String) throws -> UUID {
        let context = ModelContext(container)
        let item = ClipboardItem(
            type: .text, previewText: "", contentHash: UUID().uuidString, byteSize: rtf.utf8.count,
            deviceID: "test", sequenceNumber: 1
        )
        let envelope = try BlobEncryption().encrypt(
            Data(rtf.utf8), associatedData: BlobEncryption.associatedData(itemID: item.id, field: .blob)
        )
        let blob = ClipboardBlob(encryptedData: envelope.ciphertext, nonceData: envelope.nonce, mimeType: "public.rtf")
        blob.aadBound = true
        item.blob = blob
        context.insert(item)
        context.insert(blob)
        try context.save()
        return item.id
    }

    private func item(_ id: UUID) throws -> ClipboardItem {
        try #require(ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first { $0.id == id })
    }

    @Test("a number that was stored as a colour becomes text, with its preview sealed")
    func repair_numberStoredAsColour_becomesText() async throws {
        let number = try insertColorClip("20231234")
        let real = try insertColorClip("#FF8800")
        let bareHex = try insertColorClip("FF8800")

        let result = try await StorageService(modelContainer: container).repairMisreadClips()

        #expect(result.reclassified == 1)
        let repaired = try item(number)
        #expect(repaired.type == .text)
        #expect(repaired.previewText.isEmpty, "a text preview is stored sealed, never in the clear")
        #expect(repaired.displayPreviewText == "20231234")
        #expect(repaired.textLength == 8)
        #expect(try item(real).type == .color)
        #expect(try item(bareHex).type == .color)
    }

    @Test("a reference number and a plain word that were stored as colours become text, sealed; real colours stay")
    func repair_referenceAndWordStoredAsColour_becomeText() async throws {
        let reference = try insertColorClip("#178")
        let word = try insertColorClip("decade")
        let gray = try insertColorClip("#999")
        let green = try insertColorClip("#2f7a49")
        let bare = try insertColorClip("a1b2c3")

        let result = try await StorageService(modelContainer: container).repairMisreadClips()

        #expect(result.reclassified == 2)
        for id in [reference, word] {
            let repaired = try item(id)
            #expect(repaired.type == .text)
            #expect(repaired.previewText.isEmpty, "a text preview is stored sealed, never in the clear")
        }
        #expect(try item(reference).displayPreviewText == "#178")
        #expect(try item(word).displayPreviewText == "decade")
        for id in [gray, green, bare] {
            #expect(try item(id).type == .color)
        }
    }

    @Test("a wrapped secret that was stored as a colour is sealed and retyped; a card number in it is masked (R-01)")
    func repair_wrappedSecretStoredAsColour_isSealed() async throws {
        let secret = try insertColorClip("rgb(password=hunter2-Correct-Horse-Battery)")
        let card = try insertColorClip("hsl(4242 4242 4242 4242)")
        let real = try insertColorClip("rgb(12, 34, 56)")

        let result = try await StorageService(modelContainer: container).repairMisreadClips()

        #expect(result.reclassified == 2)
        let sealed = try item(secret)
        #expect(sealed.type == .text)
        #expect(sealed.previewText.isEmpty, "the wrapped password must not stay in the clear")
        #expect(sealed.displayPreviewText == "rgb(password=hunter2-Correct-Horse-Battery)")
        let masked = try item(card)
        #expect(!masked.previewText.contains("4242 4242 4242 4242"))
        #expect(masked.sensitivityRaw != nil)
        #expect(try item(real).type == .color)
    }

    @Test("an imported rich-text clip with no preview gets its text, a plain-text blob and a fresh hash")
    func repair_emptyRichTextClip_isRebuilt() async throws {
        let id = try insertEmptyRichTextClip(#"{\rtf1\ansi Call the gas company}"#)
        let before = try item(id).contentHash

        let result = try await StorageService(modelContainer: container).repairMisreadClips()

        #expect(result.rebuilt == 1)
        let repaired = try item(id)
        #expect(repaired.displayPreviewText == "Call the gas company")
        #expect(repaired.previewText.isEmpty)
        #expect(repaired.blob?.decryptedText() == "Call the gas company")
        #expect(repaired.blob?.mimeType == "public.utf8-plain-text")
        #expect(repaired.contentHash != before)
        #expect(repaired.textLength == 20)
    }

    @Test("running the repair again changes nothing")
    func repair_isIdempotent() async throws {
        _ = try insertColorClip("123456")
        _ = try insertEmptyRichTextClip(#"{\rtf1\ansi Meter reading}"#)
        let service = StorageService(modelContainer: container)

        _ = try await service.repairMisreadClips()
        let second = try await service.repairMisreadClips()

        #expect(second.reclassified == 0)
        #expect(second.rebuilt == 0)
    }

    @Test("a rich-text clip that holds no text is left alone")
    func repair_emptyRichTextWithNoText_isLeftAlone() async throws {
        let id = try insertEmptyRichTextClip(#"{\rtf1\ansi }"#)

        let result = try await StorageService(modelContainer: container).repairMisreadClips()

        #expect(result.rebuilt == 0)
        #expect(try item(id).blob?.mimeType == "public.rtf")
    }

    @Test("an auto-created Snippets collection that only holds the first-run sample is removed")
    func repair_sampleSnippetsPinboard_isRemovedUnlessUserAddedOtherClips() async throws {
        let context = ModelContext(container)
        let pinboard = Pinboard(name: "Snippets", symbolName: "folder.fill", colorHex: "#2F8B4C", sortOrder: 0)
        let sample = ClipboardItem(
            type: .text,
            previewText: "Thanks",
            contentHash: UUID().uuidString,
            byteSize: 6,
            deviceID: "test",
            sequenceNumber: 1,
            isPinned: true
        )
        sample.customTitle = FirstRunSamples.snippetTitle
        sample.collectionID = pinboard.id
        context.insert(pinboard)
        context.insert(sample)
        try context.save()

        _ = try await StorageService(modelContainer: container).repairMisreadClips()

        let remaining = try ModelContext(container).fetch(FetchDescriptor<Pinboard>())
        #expect(remaining.isEmpty)
        let keptSample = try #require(ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first)
        #expect(keptSample.isPinned)
        #expect(keptSample.collectionID == nil)
    }
}
