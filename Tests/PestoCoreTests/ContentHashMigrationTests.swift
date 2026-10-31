// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("Fingerprints of clips are keyed, and old ones are upgraded")
struct ContentHashMigrationTests {
    private let container: ModelContainer
    private let service: StorageService

    init() async throws {
        container = try ModelContainerSetup.makeInMemory()
        service = StorageService(modelContainer: container)
    }

    private func plain(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func capture(_ text: String) -> PasteboardCapture {
        PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
            contentHash: plain(text)
        )
    }

    private func items() throws -> [ClipboardItem] {
        try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
    }

    private func makeLegacy(_ text: String) throws {
        let context = ModelContext(container)
        let item = try #require(try context.fetch(FetchDescriptor<ClipboardItem>()).first)
        item.contentHash = plain(text)
        try context.save()
    }

    @Test("a new clip is stored under a keyed hash, never the plain SHA-256, and copying it again still dedupes")
    func whenIngested_thenKeyedAndDeduped() async throws {
        try await service.ingest(capture("123-45-6789 is not a real number"))
        try await service.ingest(capture("123-45-6789 is not a real number"))

        let stored = try items()
        #expect(stored.count == 1)
        #expect(try ContentHash.isKeyed(#require(stored.first).contentHash))
        #expect(stored.first?.contentHash != plain("123-45-6789 is not a real number"))
    }

    @Test("a clip stored under the old plain hash is found by a fresh copy and upgraded in place")
    func whenLegacyItemRecopied_thenDedupedAndUpgraded() async throws {
        let text = "legacy clip"
        try await service.ingest(capture(text))
        try makeLegacy(text)
        #expect(try items().first?.contentHash == plain(text))

        // A fresh service instance: the first one suppresses an identical copy within two seconds (paste echo).
        let later = StorageService(modelContainer: container)
        try await later.ingest(capture(text))

        let stored = try items()
        #expect(stored.count == 1, "the old item must be found, not duplicated")
        #expect(try ContentHash.isKeyed(#require(stored.first).contentHash))
    }

    @Test("the migration keys every old hash, is idempotent, and keeps duplicates findable")
    func whenMigrated_thenKeyedIdempotentAndStillDedupes() async throws {
        let text = "another legacy clip"
        try await service.ingest(capture(text))
        try makeLegacy(text)

        #expect(try await service.migrateContentHashes() == 1)
        #expect(try await service.migrateContentHashes() == 0, "a second run must change nothing")
        #expect(try items().allSatisfy { ContentHash.isKeyed($0.contentHash) })

        try await service.ingest(capture(text))
        #expect(try items().count == 1, "a copy after the migration must still find the migrated item")
    }
}
