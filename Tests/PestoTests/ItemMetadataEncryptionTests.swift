// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import PestoCore
import SwiftData
import Testing
@testable import Pesto

/// Clips ingested one second apart, so the order the tests read them back in never depends on the wall clock.
private final class SpacedTimestamps: @unchecked Sendable {
    private let lock = NSLock()
    private var next = Date(timeIntervalSince1970: 1000)

    func take() -> Date {
        lock.withLock {
            defer { next = next.addingTimeInterval(1) }
            return next
        }
    }
}

extension HostedGlobals {
    @Suite("Titles, notes, tags and page titles are encrypted at rest", .serialized)
    struct ItemMetadataEncryptionTests {
        private let container: ModelContainer
        private let service: StorageService
        private let timestamps = SpacedTimestamps()

        init() async throws {
            container = try ModelContainerSetup.makeInMemory().synced
            service = StorageService(modelContainer: container)
        }

        private func ingest(_ text: String) async throws {
            try await service.ingest(PasteboardCapture(
                typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
                timestamp: timestamps.take(),
                contentHash: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
            ))
        }

        private func firstItem(in context: ModelContext) throws -> ClipboardItem {
            try #require(context.fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp)])).first)
        }

        @Test("what is set reads back, and the readable columns hold nothing")
        func whenMetadataSet_thenReadableAndNotStoredInTheClear() async throws {
            try await ingest("a clip")
            let context = ModelContext(container)
            let item = try firstItem(in: context)

            item.customTitle = "Quarterly figures"
            item.userNote = "Ask Dana before sending"
            item.tags = ["finance", "q3"]
            item.ogTitle = "Acme Annual Report"
            item.ogSiteName = "acme.example"
            try context.save()

            let reread = try firstItem(in: ModelContext(container))
            #expect(reread.customTitle == "Quarterly figures")
            #expect(reread.userNote == "Ask Dana before sending")
            #expect(reread.tags == ["finance", "q3"])
            #expect(reread.ogTitle == "Acme Annual Report")
            #expect(reread.ogSiteName == "acme.example")
            #expect(reread.legacyCustomTitle == nil)
            #expect(reread.legacyUserNote == nil)
            #expect(reread.legacyTagsRaw.isEmpty)
            #expect(reread.legacyOgTitle == nil)
            #expect(reread.legacyOgSiteName == nil)
            let sealed = try #require(reread.metadataCiphertext)
            #expect(sealed.range(of: Data("Quarterly".utf8)) == nil)
            #expect(sealed.range(of: Data("finance".utf8)) == nil)
        }

        @Test("clearing every field leaves nothing stored")
        func whenAllCleared_thenNoCiphertext() async throws {
            try await ingest("a clip")
            let context = ModelContext(container)
            let item = try firstItem(in: context)
            item.customTitle = "Title"
            item.customTitle = nil

            #expect(item.metadataCiphertext == nil)
            #expect(item.customTitle == nil)
            #expect(item.tags.isEmpty)
        }

        @Test("a title moved to another clip no longer opens")
        func whenCiphertextSwapped_thenNeitherReadsBack() async throws {
            try await ingest("first")
            try await ingest("second")
            let context = ModelContext(container)
            let all = try context.fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp)]))
            let a = try #require(all.first)
            let b = try #require(all.last)
            a.customTitle = "Title of the first"
            b.customTitle = "Title of the second"
            (a.metadataCiphertext, b.metadataCiphertext) = (b.metadataCiphertext, a.metadataCiphertext)
            (a.metadataNonce, b.metadataNonce) = (b.metadataNonce, a.metadataNonce)
            try context.save()

            let reread = try ModelContext(container)
                .fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp)]))

            #expect(reread.first?.customTitle == nil)
            #expect(reread.last?.customTitle == nil)
        }

        @Test("the launch migration seals plaintext columns, keeps them readable and clears them")
        func whenLegacyPlaintext_thenSealedAndCleared() async throws {
            try await ingest("legacy")
            try await ingest("other")
            let context = ModelContext(container)
            let all = try context.fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp)]))
            let legacy = try #require(all.first)
            legacy.legacyCustomTitle = "Old title"
            legacy.legacyUserNote = "Old note"
            legacy.legacyTagsRaw = "alpha,beta"
            legacy.legacyOgTitle = "Old page"
            try context.save()

            // A service that has not touched these rows. The one that ingested them may still hold the objects it made,
            // with the columns as they were before this context wrote the legacy values (the test failed once in
            // fifteen
            // runs when it did), and a migration that fetches them would see nothing to seal.
            let migrator = StorageService(modelContainer: container, environment: .testing())
            let first = try await migrator.sealItemMetadata()
            let second = try await migrator.sealItemMetadata()

            let reread = try ModelContext(container)
                .fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp)]))
            let migrated = try #require(reread.first)
            #expect(first.sealed == 1 && first.failed == 0, "first pass: \(first)")
            #expect(second.sealed == 0, "second pass: \(second)")
            #expect(migrated.customTitle == "Old title")
            #expect(migrated.userNote == "Old note")
            #expect(migrated.tags == ["alpha", "beta"])
            #expect(migrated.ogTitle == "Old page")
            #expect(migrated.legacyCustomTitle == nil && migrated.legacyUserNote == nil)
            #expect(migrated.legacyTagsRaw.isEmpty && migrated.legacyOgTitle == nil)
            #expect(migrated.metadataCiphertext != nil)
            #expect(reread.last?.metadataCiphertext == nil)
        }

        @Test("an unmigrated clip still reads its plaintext columns")
        func whenNotYetMigrated_thenReadsLegacy() async throws {
            try await ingest("legacy")
            let context = ModelContext(container)
            let item = try firstItem(in: context)
            item.legacyCustomTitle = "Still readable"
            item.legacyTagsRaw = "one,two"

            #expect(item.customTitle == "Still readable")
            #expect(item.tags == ["one", "two"])
        }
    }
}
