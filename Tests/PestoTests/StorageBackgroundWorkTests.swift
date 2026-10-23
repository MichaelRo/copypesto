// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import PestoCore
import SwiftData
import Testing
@testable import Pesto

private struct FakeEmbedder: TextEmbedding {
    let vector: Data
    func embed(text _: String) async -> Data? {
        try? await Task.sleep(for: .milliseconds(50))
        return vector
    }
}

private actor RecordingEmbedder: TextEmbedding {
    private(set) var lengths: [Int] = []
    func embed(text: String) async -> Data? {
        lengths.append(text.count)
        return nil
    }
}

extension HostedGlobals {
    @Suite("Ingest background work can be awaited")
    struct StorageBackgroundWorkTests {
        private let container: ModelContainer
        private let service: StorageService

        init() async throws {
            container = try ModelContainerSetup.makeInMemory().synced
            service = StorageService(modelContainer: container)
        }

        private func ingest(_ text: String, into target: StorageService? = nil) async throws {
            try await (target ?? service).ingest(PasteboardCapture(
                typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
                timestamp: .now, contentHash: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }
                    .joined()
            ))
        }

        private func firstItem() throws -> ClipboardItem {
            try #require(ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first)
        }

        @Test("a long clip has its vector once the background work is awaited")
        func whenLongClipIngested_thenVectorStoredAfterWaiting() async throws {
            let vector = Data((0..<64).map { UInt8($0) })
            let service = StorageService(
                modelContainer: container, environment: .testing { $0.embedder = FakeEmbedder(vector: vector) }
            )

            try await ingest("quarterly numbers for the board", into: service)
            await service.waitForBackgroundWork()

            #expect(try firstItem().embeddingData == vector)
        }

        @Test("a huge clip reaches the language model capped, so one copy cannot take gigabytes")
        func whenHugeClipIngested_thenTheEmbedderGetsAtMostTheCap() async throws {
            let embedder = RecordingEmbedder()
            let service = StorageService(modelContainer: container, environment: .testing { $0.embedder = embedder })

            try await ingest(String(repeating: "quarterly numbers ", count: 20_000), into: service)
            await service.waitForBackgroundWork()

            let lengths = await embedder.lengths
            #expect(lengths == [SemanticIndexer.maxEmbeddedCharacters])
        }

        @Test("a hosted test that injects nothing never loads the real language model")
        func whenNoEmbedderInjected_thenNothingIsEmbedded() async throws {
            try await ingest("quarterly numbers for the board")
            await service.waitForBackgroundWork()

            #expect(try firstItem().embeddingData == nil)
        }
    }
}
