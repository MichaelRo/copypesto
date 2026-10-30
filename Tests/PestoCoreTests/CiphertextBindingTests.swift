// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("Ciphertext is bound to its item", .serialized)
struct CiphertextBindingTests {
    private let container: ModelContainer
    private let service: StorageService

    init() async throws {
        container = try ModelContainerSetup.makeInMemory()
        service = StorageService(modelContainer: container)
    }

    private func ingest(_ text: String) async throws {
        try await service.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text, timestamp: .now,
            contentHash: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        ))
    }

    private func items() throws -> [ClipboardItem] {
        try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp)]))
    }

    /// Puts a clip back the way it was stored before binding existed: sealed without associated data.
    private func makeLegacy(_ item: ClipboardItem, in context: ModelContext) throws {
        let encryption = BlobEncryption()
        let blob = try #require(item.blob)
        let plainBlob = try #require(blob.decryptedData())
        let legacyBlob = try encryption.encrypt(plainBlob)
        blob.encryptedData = legacyBlob.ciphertext
        blob.nonceData = legacyBlob.nonce
        blob.aadBound = false
        let plainPreview = try encryption.decrypt(
            .init(ciphertext: #require(item.previewCiphertext), nonce: #require(item.previewNonce)),
            associatedData: item.previewAssociatedData
        )
        let legacyPreview = try encryption.encrypt(plainPreview)
        item.previewCiphertext = legacyPreview.ciphertext
        item.previewNonce = legacyPreview.nonce
        item.previewAADBound = false
        try context.save()
    }

    @Test("a new clip is bound, and still reads back")
    func whenIngested_thenBoundAndReadable() async throws {
        try await ingest("a freshly copied clip")

        let item = try #require(items().first)

        #expect(item.previewAADBound)
        #expect(item.blob?.aadBound == true)
        #expect(item.displayPreviewText == "a freshly copied clip")
        #expect(item.blob?.decryptedText() == "a freshly copied clip")
    }

    @Test("a blob moved to another clip no longer opens")
    func whenBlobSwapped_thenNeitherOpens() async throws {
        try await ingest("first clip")
        try await ingest("second clip")
        let context = ModelContext(container)
        let all = try context.fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp)]))
        let a = try #require(all.first?.blob)
        let b = try #require(all.last?.blob)
        (a.encryptedData, b.encryptedData) = (b.encryptedData, a.encryptedData)
        (a.nonceData, b.nonceData) = (b.nonceData, a.nonceData)
        try context.save()

        let reread = try ModelContext(container)
            .fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp)]))

        #expect(reread.first?.blob?.decryptedData() == nil)
        #expect(reread.last?.blob?.decryptedData() == nil)
    }

    @Test("a preview moved to another clip no longer opens, so it cannot be pasted in its place")
    func whenPreviewSwapped_thenWrongTextIsNotShown() async throws {
        try await ingest("first clip")
        try await ingest("second clip")
        let context = ModelContext(container)
        let all = try context.fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp)]))
        let (first, second) = try (#require(all.first), #require(all.last))
        (first.previewCiphertext, second.previewCiphertext) = (second.previewCiphertext, first.previewCiphertext)
        (first.previewNonce, second.previewNonce) = (second.previewNonce, first.previewNonce)
        try context.save()

        let reread = try ModelContext(container)
            .fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp)]))

        #expect(reread.first?.displayPreviewText != "second clip")
        #expect(reread.last?.displayPreviewText != "first clip")
    }

    @Test("older clips are converted, still read the same, and a second run changes nothing")
    func whenLegacyRows_thenConvertedOnce() async throws {
        try await ingest("old clip one")
        try await ingest("old clip two")
        let context = ModelContext(container)
        for item in try context.fetch(FetchDescriptor<ClipboardItem>()) {
            try makeLegacy(item, in: context)
        }
        #expect(try items().allSatisfy { !$0.previewAADBound && $0.blob?.aadBound == false })

        let first = try await service.bindCiphertextToItems(batchSize: 1)
        let second = try await service.bindCiphertextToItems()

        #expect(first.converted == 4 && first.failed == 0)
        #expect(second.converted == 0 && second.failed == 0)
        let after = try items()
        #expect(after.allSatisfy { $0.previewAADBound && $0.blob?.aadBound == true })
        #expect(after.map(\.displayPreviewText) == ["old clip one", "old clip two"])
        #expect(after.compactMap { $0.blob?.decryptedText() } == ["old clip one", "old clip two"])
    }

    @Test("a clip that cannot be read is left exactly as it was, and the others still convert")
    func whenOneRowIsUnreadable_thenItIsKeptAndCounted() async throws {
        try await ingest("good clip")
        try await ingest("damaged clip")
        let context = ModelContext(container)
        let all = try context.fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp)]))
        for item in all {
            try makeLegacy(item, in: context)
        }
        let damaged = try #require(all.last?.blob)
        var bytes = Data(damaged.encryptedData)
        bytes[0] ^= 0xFF
        damaged.encryptedData = bytes
        try context.save()

        let result = try await service.bindCiphertextToItems()

        #expect(result.failed == 1)
        let after = try items()
        #expect(after.last?.blob?.aadBound == false)
        #expect(after.last?.blob?.encryptedData == bytes)
        #expect(after.first?.blob?.decryptedText() == "good clip")
    }
}
