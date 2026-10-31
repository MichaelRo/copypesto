// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Synchronization
import Testing
@testable import PestoCore

private struct SealFailure: Error {}

private final class SwitchableSealer: Sendable {
    private let fails = Mutex(false)

    func failing(_ value: Bool) {
        fails.withLock { $0 = value }
    }

    func seal(_ data: Data, _ associatedData: Data) throws -> BlobEncryption.EncryptedEnvelope {
        if fails.withLock({ $0 }) { throw SealFailure() }
        return try BlobEncryption().encrypt(data, associatedData: associatedData)
    }
}

@Suite("A preview that cannot be sealed is never stored as plain text")
struct PreviewSealingFailsClosedTests {
    private let container: ModelContainer
    private let service: StorageService
    private let sealer = SwitchableSealer()

    init() async throws {
        container = try ModelContainerSetup.makeInMemory()
        let sealer = sealer
        service = StorageService(modelContainer: container, environment: .testing { $0.previewSealer = sealer.seal })
    }

    private func capture(_ text: String, at time: Date) -> PasteboardCapture {
        PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
            timestamp: time,
            contentHash: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        )
    }

    private func items() throws -> [ClipboardItem] {
        try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp)]))
    }

    @Test("when sealing the preview fails during ingest, the copy is refused and nothing is stored")
    func whenSealingFailsOnIngest_thenNothingIsStored() async throws {
        sealer.failing(true)

        await #expect(throws: SealFailure.self) {
            try await service.ingest(capture("a private sentence", at: Date(timeIntervalSince1970: 1000)))
        }

        #expect(try items().isEmpty)
    }

    @Test("when sealing the preview fails during an append, the clip is left as it was")
    func whenSealingFailsOnAppend_thenTheClipIsUnchanged() async throws {
        try await service.ingest(capture("first part", at: Date(timeIntervalSince1970: 1000)))
        sealer.failing(true)

        await #expect(throws: SealFailure.self) {
            try await service.appendToLatest(capture("second part", at: Date(timeIntervalSince1970: 2000)))
        }
        sealer.failing(false)
        try await service.ingest(capture("an unrelated copy", at: Date(timeIntervalSince1970: 3000)))

        let first = try #require(items().first { $0.blob?.decryptedText() == "first part" })
        #expect(first.previewText.isEmpty, "a plain preview was stored")
        #expect(first.displayPreviewText == "first part")
        #expect(try items().allSatisfy { $0.blob?.decryptedText()?.contains("second part") != true })
    }
}
