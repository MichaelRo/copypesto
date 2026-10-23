// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import PestoCore
import SwiftData
import Synchronization
import Testing
@testable import Pesto

// MARK: - Shared helpers

private func sha256Hex(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
}

private func capture(
    text: String,
    timestamp: Date = .now,
    bundleID: String? = nil
)
-> PasteboardCapture {
    PasteboardCapture(
        typeIdentifier: "public.utf8-plain-text",
        payload: Data(text.utf8),
        payloadString: text,
        frontmostBundleID: bundleID,
        timestamp: timestamp,
        contentHash: sha256Hex(text)
    )
}

// MARK: - Suite

/// Records what StorageService does to the last-item file, so tests neither share nor touch the real one.
private final class SpyLastItemStore: LastItemStoring {
    private let state = Mutex<[String]>([])
    var events: [String] {
        state.withLock { $0 }
    }

    func write(id: UUID, preview _: String, type _: String, timestamp _: Date, sourceApp _: String?) {
        state.withLock { $0.append("write \(id.uuidString)") }
    }

    func clear() {
        state.withLock { $0.append("clear") }
    }

    func clear(ifItemID id: UUID) {
        state.withLock { $0.append("clear \(id.uuidString)") }
    }
}

private struct RangeSample {
    let text: String
    let offset: TimeInterval
    let pinned: Bool
}

private struct StubRecognizer: TextRecognizing {
    let text: String?
    func recognize(imageData _: Data) async -> String? {
        text
    }
}

extension HostedGlobals {
    @Suite("StorageService ingest pipeline")
    struct StorageServiceIntegrationTests {
        private let container: ModelContainer
        private let service: StorageService
        private let lastItem = SpyLastItemStore()

        init() async throws {
            container = try ModelContainerSetup.makeInMemory().synced
            let spy = lastItem
            service = StorageService(modelContainer: container, environment: .testing { $0.lastItemStore = spy })
        }

        private func fetchItems() throws -> [ClipboardItem] {
            let ctx = ModelContext(container)
            return try ctx.fetch(FetchDescriptor<ClipboardItem>(
                sortBy: [SortDescriptor(\.timestamp)]
            ))
        }

        // MARK: - Basic ingestion

        @Test("basic text ingest stores item with correct type and preview")
        func ingest_text_storesItem() async throws {
            let cap = PasteboardCapture(
                typeIdentifier: "public.utf8-plain-text",
                payload: Data("Hello, world!".utf8),
                payloadString: "Hello, world!",
                contentHash: UUID().uuidString
            )
            try await service.ingest(cap)
            let items = try fetchItems()
            #expect(items.count == 1)
            #expect(items[0].type == .text)
            #expect(items[0].displayPreviewText == "Hello, world!")
            #expect(items[0].blob != nil)
        }

        @Test("text/code previews are stored encrypted, not plaintext (ADR 0002)")
        func ingest_text_previewIsEncrypted() async throws {
            let secret = "this string must not leak to CloudKit"
            let cap = PasteboardCapture(
                typeIdentifier: "public.utf8-plain-text",
                payload: Data(secret.utf8),
                payloadString: secret,
                contentHash: UUID().uuidString
            )
            try await service.ingest(cap)
            let items = try fetchItems()
            #expect(items.count == 1)
            let item = items[0]
            // The stored field must NOT contain the secret — it's encrypted out.
            #expect(item.previewText.isEmpty, "previewText must be empty for text items post-ADR 0002")
            #expect(item.previewCiphertext != nil, "ciphertext must be populated for text items")
            #expect(item.previewNonce != nil, "nonce must be populated for text items")
            // The display accessor round-trips back to the original plaintext.
            #expect(item.displayPreviewText == secret)
        }

        @Test("two distinct captures produce two items")
        func ingest_distinctContent_createsTwoItems() async throws {
            let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
            await service.updateClock { t0 }
            try await service.ingest(capture(text: "alpha", timestamp: t0))
            await service.updateClock { t0.addingTimeInterval(5) }
            try await service.ingest(capture(text: "beta", timestamp: t0.addingTimeInterval(5)))
            let items = try fetchItems()
            #expect(items.count == 2)
        }

        // MARK: - 30-second fast-path dedup

        @Test("second ingest with same hash within 30 s is deduplicated")
        func ingest_sameHash_within30s_isDeduped() async throws {
            let t0 = Date(timeIntervalSinceReferenceDate: 2_000_000)
            await service.updateClock { t0 }
            let cap = capture(text: "dup-fast", timestamp: t0)
            try await service.ingest(cap)
            // Same hash, 5 s later — within the 30-second window.
            await service.updateClock { t0.addingTimeInterval(5) }
            try await service.ingest(cap)
            let items = try fetchItems()
            #expect(items.count == 1)
        }

        // MARK: - Full-history dedup (outside 30-second window)

        @Test("same hash after 30 s is deduplicated by DB fetch")
        func ingest_sameHash_after30s_isDeduped() async throws {
            let t0 = Date(timeIntervalSinceReferenceDate: 3_000_000)
            let t1 = t0.addingTimeInterval(60) // 60 s > 30-second window
            await service.updateClock { t0 }
            try await service.ingest(capture(text: "db-dedup", timestamp: t0))
            // Advance the clock past the fast-path window.
            await service.updateClock { t1 }
            try await service.ingest(capture(text: "db-dedup", timestamp: t1))
            let items = try fetchItems()
            #expect(items.count == 1)
        }

        @Test("deduped item's timestamp is bumped to the latest copy time")
        func ingest_sameHash_after30s_bumpedTimestamp() async throws {
            let t0 = Date(timeIntervalSinceReferenceDate: 4_000_000)
            let t1 = t0.addingTimeInterval(90)
            await service.updateClock { t0 }
            try await service.ingest(capture(text: "rebump", timestamp: t0))
            await service.updateClock { t1 }
            try await service.ingest(capture(text: "rebump", timestamp: t1))
            let items = try fetchItems()
            #expect(items.count == 1)
            #expect(abs(items[0].timestamp.timeIntervalSince(t1)) < 1)
        }

        @Test("copying an older item again pops it back to the top of history")
        func ingest_whenItemReCopiedAfterAnother_thenBubblesToTop() async throws {
            let t0 = Date(timeIntervalSinceReferenceDate: 4_500_000)
            await service.updateClock { t0 }
            try await service.ingest(capture(text: "alpha", timestamp: t0))

            let t1 = t0.addingTimeInterval(10)
            await service.updateClock { t1 }
            try await service.ingest(capture(text: "beta", timestamp: t1))

            // Re-copy alpha. Even though it's the same content as an earlier ingest, the in-memory
            // fast-path must NOT swallow it — beta was the most recent, not alpha.
            let t2 = t1.addingTimeInterval(10)
            await service.updateClock { t2 }
            try await service.ingest(capture(text: "alpha", timestamp: t2))

            let items = try fetchItems().sorted { $0.timestamp > $1.timestamp }
            #expect(items.count == 2)
            #expect(items.first?.displayPreviewText == "alpha")
            #expect(items.last?.displayPreviewText == "beta")
        }

        @Test("three copies of same content always result in one item")
        func ingest_tripleCopy_resultsInOneItem() async throws {
            let base = Date(timeIntervalSinceReferenceDate: 5_000_000)
            await service.updateClock { base }
            try await service.ingest(capture(text: "triple", timestamp: base))
            await service.updateClock { base.addingTimeInterval(10) }
            try await service.ingest(capture(text: "triple", timestamp: base.addingTimeInterval(10)))
            // Third copy well outside the 30-second fast-path window.
            await service.updateClock { base.addingTimeInterval(120) }
            try await service.ingest(capture(text: "triple", timestamp: base.addingTimeInterval(120)))
            let items = try fetchItems()
            #expect(items.count == 1)
        }

        // MARK: - Sensitivity

        @Test("credit card number is flagged as .creditCard sensitivity")
        func ingest_creditCard_setsSensitivity() async throws {
            let cap = PasteboardCapture(
                typeIdentifier: "public.utf8-plain-text",
                payload: Data("4111 1111 1111 1111".utf8),
                payloadString: "4111 1111 1111 1111",
                contentHash: UUID().uuidString
            )
            try await service.ingest(cap)
            let items = try fetchItems()
            #expect(items.first?.sensitivity == .creditCard)
            #expect(items.first?.sensitivityMaskedPreview != nil)
        }

        // MARK: - Content classification

        @Test("URL string is classified as .url type")
        func ingest_urlString_classifiesAsURL() async throws {
            let cap = PasteboardCapture(
                typeIdentifier: "public.utf8-plain-text",
                payload: Data("https://example.com".utf8),
                payloadString: "https://example.com",
                contentHash: UUID().uuidString
            )
            try await service.ingest(cap)
            let items = try fetchItems()
            #expect(items.first?.type == .url)
        }

        @Test("Swift code snippet sets detectedLanguage to swift")
        func ingest_swiftCode_setsDetectedLanguage() async throws {
            let code = "func greet(name: String) -> String {\n" +
                "    let greeting = \"Hello, \\(name)\"\n    return greeting\n}"
            try await service.ingest(capture(text: code))
            let items = try fetchItems()
            #expect(items.first?.type == .code)
            #expect(items.first?.detectedLanguage == "swift")
        }

        @Test("plain text does not set detectedLanguage")
        func ingest_plainText_noDetectedLanguage() async throws {
            try await service.ingest(capture(text: "Pick up groceries on the way home"))
            let items = try fetchItems()
            #expect(items.first?.type == .text)
            #expect(items.first?.detectedLanguage == nil)
        }

        @Test("PNG UTI is classified as .image and blob is stored")
        func ingest_pngUTI_storesImageWithBlob() async throws {
            let pngMagic = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            let cap = PasteboardCapture(
                typeIdentifier: "public.png",
                payload: pngMagic,
                payloadString: nil,
                contentHash: UUID().uuidString
            )
            try await service.ingest(cap)
            let items = try fetchItems()
            #expect(items.first?.type == .image)
            #expect(items.first?.blob != nil)
        }

        // MARK: - Append-to-latest

        @Test("appendToLatest combines text with a newline")
        func appendToLatest_combinesTextWithNewline() async throws {
            let t0 = Date(timeIntervalSinceReferenceDate: 6_000_000)
            await service.updateClock { t0 }
            try await service.ingest(capture(text: "first line", timestamp: t0))
            await service.updateClock { t0.addingTimeInterval(1) }
            try await service.appendToLatest(capture(text: "second line", timestamp: t0.addingTimeInterval(1)))
            let items = try fetchItems()
            #expect(items.count == 1)
            #expect(items[0].displayPreviewText.contains("first line"))
            #expect(items[0].displayPreviewText.contains("second line"))
        }

        @Test("appendToLatest with no existing text item creates a new item")
        func appendToLatest_noExistingItem_createsNewItem() async throws {
            try await service.appendToLatest(capture(text: "standalone"))
            let items = try fetchItems()
            #expect(items.count == 1)
            #expect(items[0].displayPreviewText == "standalone")
        }

        // MARK: - Deletion

        // MARK: - Clearing a time range ("Last hour" used to delete everything OLDER than an hour)

        private func seedRangeFixture(now: Date) async throws {
            let stamps = [
                RangeSample(text: "two hours ago", offset: -7200, pinned: false),
                RangeSample(text: "ten minutes ago", offset: -600, pinned: false),
                RangeSample(text: "one minute ago", offset: -60, pinned: false),
                RangeSample(text: "pinned one minute ago", offset: -60, pinned: true)
            ]
            for sample in stamps {
                let text = sample.text
                let when = now.addingTimeInterval(sample.offset)
                await service.updateClock { when }
                try await service.ingest(capture(text: text, timestamp: when))
                if sample.pinned {
                    let context = ModelContext(container)
                    let forms = ContentHash.candidates(
                        for: sha256Hex(text),
                        key: try? BlobEncryption().loadOrCreateKey()
                    )
                    let item = try #require(try context.fetch(FetchDescriptor<ClipboardItem>(
                        predicate: #Predicate { forms.contains($0.contentHash) }
                    )).first)
                    item.isPinned = true
                    try context.save()
                }
            }
        }

        private func remainingTexts() throws -> [String] {
            try fetchItems().map(\.displayPreviewText)
        }

        @Test("clearing the last five minutes deletes only items newer than that")
        func clear_lastFiveMinutes_deletesOnlyRecentItems() async throws {
            let now = Date(timeIntervalSinceReferenceDate: 10_000_000)
            try await seedRangeFixture(now: now)

            let deleted = try await service.clearNonPinned(in: .lastFiveMinutes, now: now)

            #expect(deleted.count == 1)
            #expect(try Set(remainingTexts()) == ["two hours ago", "ten minutes ago", "pinned one minute ago"])
        }

        @Test("clearing the last hour keeps the older history")
        func clear_lastHour_keepsOlderHistory() async throws {
            let now = Date(timeIntervalSinceReferenceDate: 10_100_000)
            try await seedRangeFixture(now: now)

            let deleted = try await service.clearNonPinned(in: .lastHour, now: now)

            #expect(deleted.count == 2)
            #expect(try Set(remainingTexts()) == ["two hours ago", "pinned one minute ago"])
        }

        @Test("clearing everything deletes all non-pinned items and keeps pinned ones")
        func clear_all_keepsPinned() async throws {
            let now = Date(timeIntervalSinceReferenceDate: 10_200_000)
            try await seedRangeFixture(now: now)

            let deleted = try await service.clearNonPinned(in: .all, now: now)

            #expect(deleted.count == 3)
            #expect(try remainingTexts() == ["pinned one minute ago"])
        }

        @Test("the confirmation count matches what clearing would delete")
        func count_matchesWhatClearingDeletes() async throws {
            let now = Date(timeIntervalSinceReferenceDate: 10_300_000)
            try await seedRangeFixture(now: now)

            #expect(try await service.nonPinnedCount(in: .lastFiveMinutes, now: now) == 1)
            #expect(try await service.nonPinnedCount(in: .lastHour, now: now) == 2)
            #expect(try await service.nonPinnedCount(in: .all, now: now) == 3)
        }

        // MARK: - Deleting removes every trace

        @Test("deleting the latest item removes it from the last-item file")
        func deleteItem_clearsTheLastItemFile() async throws {
            try await service.ingest(capture(text: "secret-x"))
            let item = try #require(try fetchItems().first)

            _ = try await service.deleteItem(id: item.id)

            #expect(lastItem.events.contains("clear \(item.id.uuidString)"))
        }

        @Test("deleting items records a tombstone for each and clears their last-item entry")
        func deleteItems_tombstonesAndClears() async throws {
            try await service.ingest(capture(text: "one"))
            try await service.ingest(capture(text: "two", timestamp: .now.addingTimeInterval(1)))
            let ids = try fetchItems().map(\.id)

            let deleted = try await service.deleteItems(ids: ids, reason: .user)

            #expect(deleted == 2)
            #expect(try fetchItems().isEmpty)
            #expect(try ModelContext(container).fetch(FetchDescriptor<DeletedItemTombstone>()).count == 2)
            for id in ids {
                #expect(lastItem.events.contains("clear \(id.uuidString)"))
            }
        }

        @Test("with the history lock on, the last-item file is not written, since it is readable without the lock")
        func ingest_withTheLockOn_doesNotWriteTheLastItemFile() async throws {
            AppDefaults.store.set(true, forKey: "biometricLockEnabled")
            defer { AppDefaults.store.removeObject(forKey: "biometricLockEnabled") }

            try await service.ingest(capture(text: "locked-away"))

            #expect(!lastItem.events.contains { $0.hasPrefix("write") })
        }

        @Test("clearing history clears the last-item file")
        func clearNonPinned_clearsTheLastItemFile() async throws {
            try await service.ingest(capture(text: "secret-y"))

            try await service.clearNonPinned(in: .all)

            #expect(lastItem.events.contains("clear"))
        }

        // MARK: - Previews are encrypted and scanned for every type

        private func imageCapture(seed: String) -> PasteboardCapture {
            let bytes = Data("not-really-a-png-\(seed)".utf8)
            return PasteboardCapture(
                typeIdentifier: "public.png",
                payload: bytes,
                payloadString: nil,
                contentHash: sha256Hex(seed)
            )
        }

        @Test("a secret found by OCR in a screenshot is masked, never stored as plaintext")
        func ingest_imageWithSecretInOCRText_masksIt() async throws {
            let secret = "sk-ant-api03-EXAMPLEEXAMPLEEXAMPLEEXAMPLE1234567890abcdef"
            let service = StorageService(
                modelContainer: container,
                environment: .testing { $0.textRecognizer = StubRecognizer(text: "config\n\(secret)") }
            )

            try await service.ingest(imageCapture(seed: "secret-shot"))
            await service.waitForBackgroundWork()

            let item = try #require(try fetchItems().first)
            #expect(item.sensitivityRaw != nil, "OCR text must be scanned for secrets")
            #expect(!item.previewText.contains("sk-ant-api03"))
            #expect(!(item.sensitivityMaskedPreview ?? "").contains("EXAMPLEEXAMPLE"))
            #expect(!item.gridPreview.contains("EXAMPLEEXAMPLE"))
        }

        @Test("ordinary OCR text is stored only as ciphertext")
        func ingest_imageWithOCRText_encryptsPreview() async throws {
            let service = StorageService(
                modelContainer: container,
                environment: .testing { $0.textRecognizer = StubRecognizer(text: "Meeting at noon") }
            )

            try await service.ingest(imageCapture(seed: "plain-shot"))
            await service.waitForBackgroundWork()

            let item = try #require(try fetchItems().first)
            #expect(item.previewText.isEmpty)
            #expect(item.previewCiphertext != nil)
            #expect(item.displayPreviewText == "Meeting at noon")
        }

        @Test("a URL is stored only as ciphertext, since a link can carry a token")
        func ingest_url_encryptsPreview() async throws {
            let link = "https://example.com/reset?token=abc123"
            try await service.ingest(capture(text: link))

            let item = try #require(try fetchItems().first)
            #expect(item.type == .url)
            #expect(item.previewText.isEmpty)
            #expect(item.displayPreviewText == link)
        }

        @Test("a colour keeps its plain preview: it is not sensitive")
        func ingest_color_keepsPlainPreview() async throws {
            try await service.ingest(capture(text: "#FF5733"))

            let item = try #require(try fetchItems().first)
            #expect(item.type == .color)
            #expect(item.previewText == "#FF5733")
        }

        @Test("the migration encrypts plaintext previews from before, once")
        func migration_encryptsLegacyPlaintextPreviews() async throws {
            let context = ModelContext(container)
            func legacy(
                _ type: ClipboardType,
                _ text: String,
                hash: String,
                sensitivity: String? = nil
            )
            -> ClipboardItem {
                let item = ClipboardItem(
                    timestamp: .now,
                    type: type,
                    previewText: text,
                    contentHash: hash,
                    byteSize: text.utf8.count,
                    deviceID: "d",
                    sequenceNumber: 1
                )
                item.sensitivityRaw = sensitivity
                return item
            }
            let url = legacy(.url, "https://example.com/a", hash: "h-url")
            let color = legacy(.color, "#112233", hash: "h-color")
            let masked = legacy(.text, "•••• 4242", hash: "h-masked", sensitivity: "credit_card")
            [url, color, masked].forEach(context.insert)
            try context.save()

            #expect(try await service.encryptLegacyPreviews() == 1)

            let after = try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
            let migrated = try #require(after.first { $0.contentHash == "h-url" })
            #expect(migrated.previewText.isEmpty)
            #expect(migrated.displayPreviewText == "https://example.com/a")
            #expect(after.first { $0.contentHash == "h-color" }?.previewText == "#112233")
            #expect(after.first { $0.contentHash == "h-masked" }?.previewText == "•••• 4242")
            #expect(try await service.encryptLegacyPreviews() == 0, "running it again must change nothing")
        }

        @Test("deleteItem by ID removes exactly that item")
        func deleteItem_byID_removesSingleItem() async throws {
            let t0 = Date(timeIntervalSinceReferenceDate: 9_000_000)
            await service.updateClock { t0 }
            try await service.ingest(capture(text: "target", timestamp: t0))
            let items = try fetchItems()
            let targetID = try #require(items.first?.id)
            let deleted = try await service.deleteItem(id: targetID)
            #expect(deleted == true)
            #expect(try fetchItems().isEmpty)
        }

        @Test("deleteItem with unknown ID returns false")
        func deleteItem_unknownID_returnsFalse() async throws {
            let result = try await service.deleteItem(id: UUID())
            #expect(result == false)
        }
    }
}
