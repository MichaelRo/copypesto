// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import PestoCore
import SwiftData
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("Search vectors are encrypted at rest", .serialized)
    struct EmbeddingEncryptionTests {
        private let container: ModelContainer
        private let service: StorageService
        private let vector = Data((0..<256).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ 3) })

        init() async throws {
            container = try ModelContainerSetup.makeInMemory().synced
            service = StorageService(modelContainer: container)
        }

        private func ingest(_ text: String) async throws {
            try await service.ingest(PasteboardCapture(
                typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
                timestamp: .now,
                contentHash: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
            ))
        }

        private func items(in context: ModelContext) throws -> [ClipboardItem] {
            try context.fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp)]))
        }

        @Test("a vector that is set reads back, and the readable column holds nothing")
        func whenVectorSet_thenReadableAndNotStoredInTheClear() async throws {
            try await ingest("basil")
            let context = ModelContext(container)
            let item = try #require(try items(in: context).first)

            item.embeddingData = vector
            try context.save()

            let reread = try #require(try items(in: ModelContext(container)).first)
            #expect(reread.embeddingData == vector)
            #expect(reread.legacyEmbeddingData == nil)
            let sealed = try #require(reread.embeddingCiphertext)
            #expect(sealed.range(of: vector.prefix(32)) == nil, "the vector is stored in the clear")
        }

        @Test("clearing the vector leaves nothing stored")
        func whenVectorCleared_thenNothingStored() async throws {
            try await ingest("basil")
            let context = ModelContext(container)
            let item = try #require(try items(in: context).first)
            item.embeddingData = vector

            item.embeddingData = nil

            #expect(item.embeddingData == nil)
            #expect(item.embeddingCiphertext == nil && item.legacyEmbeddingData == nil)
        }

        @Test("a vector moved to another clip no longer opens")
        func whenCiphertextSwapped_thenNeitherReadsBack() async throws {
            try await ingest("pesto")
            try await ingest("pasta")
            let context = ModelContext(container)
            let all = try items(in: context)
            let a = try #require(all.first)
            let b = try #require(all.last)
            a.embeddingData = vector
            b.embeddingData = Data(vector.reversed())
            (a.embeddingCiphertext, b.embeddingCiphertext) = (b.embeddingCiphertext, a.embeddingCiphertext)
            (a.embeddingNonce, b.embeddingNonce) = (b.embeddingNonce, a.embeddingNonce)
            try context.save()

            let reread = try items(in: ModelContext(container))

            #expect(reread.first?.embeddingData == nil)
            #expect(reread.last?.embeddingData == nil)
        }

        @Test("the launch migration seals plaintext vectors, keeps them readable and clears them")
        func whenLegacyVector_thenSealedAndCleared() async throws {
            try await ingest("legacy")
            try await ingest("plain")
            let context = ModelContext(container)
            let legacy = try #require(try items(in: context).first)
            legacy.legacyEmbeddingData = vector
            try context.save()

            let first = try await service.sealEmbeddings()
            let second = try await service.sealEmbeddings()

            let reread = try items(in: ModelContext(container))
            let migrated = try #require(reread.first)
            #expect(first.sealed == 1 && first.failed == 0)
            #expect(second.sealed == 0)
            #expect(migrated.embeddingData == vector)
            #expect(migrated.legacyEmbeddingData == nil)
            #expect(migrated.embeddingCiphertext != nil)
            #expect(reread.last?.embeddingCiphertext == nil)
        }

        @Test("an unmigrated clip still reads its plaintext vector")
        func whenNotYetMigrated_thenReadsLegacy() async throws {
            try await ingest("legacy")
            let context = ModelContext(container)
            let item = try #require(try items(in: context).first)
            item.legacyEmbeddingData = vector

            #expect(item.embeddingData == vector)
        }

        @Test("opening five thousand sealed vectors for a search stays quick")
        func whenFiveThousandVectors_thenAColdSearchReadIsQuick() throws {
            let context = ModelContext(container)
            let blob = Data(repeating: 0x5A, count: 2048)
            for index in 0..<5000 {
                let item = ClipboardItem(
                    type: .text, previewText: "c\(index)", contentHash: "h\(index)", byteSize: 4,
                    deviceID: "d", sequenceNumber: Int64(index)
                )
                item.embeddingData = blob
                context.insert(item)
            }
            try context.save()
            PreviewTextCache.shared.clear()

            let reading = ModelContext(container)
            let all = try reading.fetch(FetchDescriptor<ClipboardItem>())
            let started = ContinuousClock.now
            let opened = all.compactMap(\.embeddingData).count
            let elapsed = started.duration(to: .now)

            #expect(opened == 5000)
            #expect(elapsed < .seconds(2), "opening 5,000 vectors took \(elapsed)")
        }
    }
}
