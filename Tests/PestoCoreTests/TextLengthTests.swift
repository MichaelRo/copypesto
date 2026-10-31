// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("A text clip remembers its full length", .serialized)
struct TextLengthTests {
    private let container: ModelContainer
    private let service: StorageService

    init() async throws {
        container = try ModelContainerSetup.makeInMemory()
        service = StorageService(modelContainer: container)
    }

    private func ingest(_ text: String, type: String = "public.utf8-plain-text") async throws {
        try await service.ingest(PasteboardCapture(
            typeIdentifier: type, payload: Data(text.utf8), payloadString: text, timestamp: .now,
            contentHash: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        ))
    }

    private func items() throws -> [ClipboardItem] {
        try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
    }

    @Test("a long clip keeps its real character count even though the preview stops at 500")
    func whenLongText_thenFullLengthStored() async throws {
        try await ingest(String(repeating: "abc ", count: 300))

        let item = try #require(items().first)

        #expect(item.textLength == 1200)
        #expect(item.displayPreviewText.count == 500)
    }

    @Test("characters are counted, not bytes")
    func whenNonLatinText_thenCharactersCounted() async throws {
        try await ingest("שלום עולם")

        #expect(try #require(items().first).textLength == 9)
    }

    @Test("a link has no character count")
    func whenURL_thenZero() async throws {
        try await ingest("https://copypesto.net", type: "public.url")

        #expect(try #require(items().first).textLength == 0)
    }
}
