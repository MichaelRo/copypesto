// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("Counting what a restore would do, without doing it", .serialized)
struct BackupRestorePreviewTests {
    private let source: ModelContainer
    private let target: ModelContainer
    private let sourceService: StorageService
    private let targetService: StorageService
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    init() async throws {
        source = try ModelContainerSetup.makeInMemory().synced
        target = try ModelContainerSetup.makeInMemory().synced
        sourceService = StorageService(modelContainer: source)
        targetService = StorageService(modelContainer: target)
    }

    private func ingest(_ text: String, minutesAgo: Double, into service: StorageService) async throws {
        let payload = Data(text.utf8)
        try await service.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: payload, payloadString: text,
            frontmostBundleID: "com.apple.Notes", timestamp: base.addingTimeInterval(-minutesAgo * 60),
            contentHash: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        ))
    }

    /// Two clips, one collection, and a clip the person deleted on purpose.
    private func fillSource() async throws {
        try await ingest("ship on friday", minutesAgo: 30, into: sourceService)
        try await ingest("a second clip", minutesAgo: 20, into: sourceService)
        try await ingest("deleted on purpose", minutesAgo: 5, into: sourceService)
        let context = ModelContext(source)
        context.insert(Pinboard(name: "Ship", symbolName: "shippingbox", colorHex: "#2F7A49", sortOrder: 0))
        try context.save()
        let doomed = try #require(context.fetch(FetchDescriptor<ClipboardItem>())
            .first { $0.displayPreviewText == "deleted on purpose" })
        _ = try await sourceService.deleteItems(ids: [doomed.id], reason: .user)
    }

    private func verified() async throws -> (VerifiedBackup, URL) {
        let export = try await sourceService.backupRecords(includeSensitive: false)
        let data = try BackupFile.write(
            records: export.records, origin: BackupOrigin(sequence: 1, deviceID: "test", createdAt: base),
            key: BackupKey.generate(), passphrase: "correct horse battery staple", iterations: 1000
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("preview-\(UUID().uuidString)")
        try data.write(to: url)
        return try (BackupFile.verify(url: url, credential: .passphrase("correct horse battery staple")), url)
    }

    private func count<T: PersistentModel>(_: T.Type, in container: ModelContainer) throws -> Int {
        try ModelContext(container).fetchCount(FetchDescriptor<T>())
    }

    @Test("on an empty Mac every clip would be added and the collection is new")
    func whenTheMacIsEmpty_thenEverythingWouldBeAdded() async throws {
        try await fillSource()
        let (backup, url) = try await verified()
        defer { try? FileManager.default.removeItem(at: url) }

        let preview = try await targetService.previewRestore(backup)

        #expect(preview == BackupRestorePreview(
            wouldAdd: 2,
            alreadyHere: 0,
            deletedHere: 0,
            newCollections: 1,
            wouldRemove: 0
        ))
    }

    @Test("a clip this Mac already has, by content, is counted as already here")
    func whenAClipIsAlreadyHere_thenItIsCountedSeparately() async throws {
        try await fillSource()
        try await ingest("a second clip", minutesAgo: 1, into: targetService)
        let (backup, url) = try await verified()
        defer { try? FileManager.default.removeItem(at: url) }

        let preview = try await targetService.previewRestore(backup)

        #expect(preview.wouldAdd == 1)
        #expect(preview.alreadyHere == 1)
    }

    @Test("a clip this Mac deleted on purpose stays deleted, so the preview does not count it as new")
    func whenAClipWasDeletedHere_thenItIsCountedAsDeleted() async throws {
        try await fillSource()
        let (backup, url) = try await verified()
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await targetService.restore(backup)
        let context = ModelContext(target)
        let shipped = try #require(context.fetch(FetchDescriptor<ClipboardItem>())
            .first { $0.displayPreviewText == "ship on friday" })
        _ = try await targetService.deleteItems(ids: [shipped.id], reason: .user)

        let preview = try await targetService.previewRestore(backup)

        #expect(preview == BackupRestorePreview(
            wouldAdd: 0,
            alreadyHere: 1,
            deletedHere: 1,
            newCollections: 0,
            wouldRemove: 0
        ))
    }

    @Test("looking changes nothing: no clip, collection or deletion is written")
    func whenPreviewed_thenNothingIsWritten() async throws {
        try await fillSource()
        let (backup, url) = try await verified()
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try await targetService.previewRestore(backup)

        #expect(try count(ClipboardItem.self, in: target) == 0)
        #expect(try count(Pinboard.self, in: target) == 0)
        #expect(try count(DeletedItemTombstone.self, in: target) == 0)
    }

    @Test("a deletion in the backup would remove a clip that is here, and the preview says so")
    func whenTheBackupDeletedAClipThatIsHere_thenItWouldBeRemoved() async throws {
        try await ingest("remove me", minutesAgo: 10, into: sourceService)
        let sourceContext = ModelContext(source)
        let doomed = try #require(sourceContext.fetch(FetchDescriptor<ClipboardItem>()).first)
        let first = try await verified()
        _ = try await targetService.restore(first.0)
        try? FileManager.default.removeItem(at: first.1)
        _ = try await sourceService.deleteItems(ids: [doomed.id], reason: .user)
        let (second, url) = try await verified()
        defer { try? FileManager.default.removeItem(at: url) }

        let preview = try await targetService.previewRestore(second)

        #expect(preview.wouldRemove == 1)
        #expect(try count(ClipboardItem.self, in: target) == 1)
    }
}
