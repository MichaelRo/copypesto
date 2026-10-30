// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Synchronization
import Testing
@testable import PestoCore

@Suite("Backing up and restoring a history", .serialized)
struct BackupRoundTripTests {
    private let source: ModelContainer
    private let target: ModelContainer
    private let sourceService: StorageService
    private let targetService: StorageService
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    init() async throws {
        source = try ModelContainerSetup.makeInMemory()
        target = try ModelContainerSetup.makeInMemory()
        sourceService = StorageService(modelContainer: source)
        targetService = StorageService(modelContainer: target)
    }

    private func ingest(_ text: String, minutesAgo: Double, into service: StorageService? = nil) async throws {
        let payload = Data(text.utf8)
        try await (service ?? sourceService).ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: payload, payloadString: text,
            frontmostBundleID: "com.apple.Notes", timestamp: base.addingTimeInterval(-minutesAgo * 60),
            contentHash: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        ))
    }

    private func items(in container: ModelContainer) throws -> [ClipboardItem] {
        try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp)]))
    }

    /// A history with a curated clip, a plain one, a card number and one the user deleted on purpose.
    private func fillSource() async throws -> UUID {
        try await ingest("ship on friday", minutesAgo: 30)
        try await ingest("a second clip", minutesAgo: 20)
        try await ingest("4111 1111 1111 1111", minutesAgo: 10)
        try await ingest("deleted on purpose", minutesAgo: 5)
        let context = ModelContext(source)
        let board = Pinboard(name: "Ship", symbolName: "shippingbox", colorHex: "#2F7A49", sortOrder: 0)
        context.insert(board)
        let all = try context.fetch(FetchDescriptor<ClipboardItem>())
        let plan = try #require(all.first { $0.displayPreviewText == "ship on friday" })
        plan.customTitle = "Plan"
        plan.userNote = "check twice"
        plan.tags = ["ops", "weekly"]
        plan.isPinned = true
        plan.collectionID = board.id
        plan.pinnedHotkeyIndex = 2
        let doomed = try #require(all.first { $0.displayPreviewText == "deleted on purpose" })
        try context.save()
        _ = try await sourceService.deleteItems(ids: [doomed.id], reason: .user)
        return plan.id
    }

    private func roundTrip(includeSensitive: Bool) async throws -> BackupContents {
        let export = try await sourceService.backupRecords(includeSensitive: includeSensitive)
        let key = BackupKey.generate()
        let file = try BackupFile.write(
            records: export.records, origin: BackupOrigin(sequence: 1, deviceID: "test", createdAt: base),
            key: key, passphrase: "correct horse battery staple", iterations: 1000
        )
        return try BackupFile.read(file, credential: .recoveryKey(key))
    }

    private func verifiedFile(includeSensitive: Bool) async throws -> (backup: VerifiedBackup, url: URL) {
        let export = try await sourceService.backupRecords(includeSensitive: includeSensitive)
        let data = try BackupFile.write(
            records: export.records, origin: BackupOrigin(sequence: 1, deviceID: "test", createdAt: base),
            key: BackupKey.generate(), passphrase: "correct horse battery staple", iterations: 1000
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("restore-\(UUID().uuidString)")
        try data.write(to: url)
        return try (BackupFile.verify(url: url, credential: .passphrase("correct horse battery staple")), url)
    }

    @Test("restoring from a verified file brings back the same clips, with the same summary, as restoring from memory")
    func whenRestoredFromFile_thenSameAsFromMemory() async throws {
        let planID = try await fillSource()
        let (backup, url) = try await verifiedFile(includeSensitive: false)
        defer { try? FileManager.default.removeItem(at: url) }

        let summary = try await targetService.restore(backup)

        let expected = try await {
            let other = try ModelContainerSetup.makeInMemory()
            let service = StorageService(modelContainer: other)
            return try await service.restore(roundTrip(includeSensitive: false))
        }()
        #expect(summary.restored == expected.restored && summary.failed == expected.failed)
        #expect(summary.keptDeleted == expected.keptDeleted && summary.alreadyHad == expected.alreadyHad)
        let restored = try items(in: target)
        #expect(restored.count == 2)
        let plan = try #require(restored.first { $0.id == planID })
        #expect(plan.customTitle == "Plan" && plan.userNote == "check twice" && plan.tags == ["ops", "weekly"])
        #expect(plan.isPinned && plan.pinnedHotkeyIndex == 2)
        let board = try #require(ModelContext(target).fetch(FetchDescriptor<Pinboard>()).first)
        #expect(plan.collectionID == board.id)
    }

    @Test("restoring from a verified file twice adds nothing")
    func whenRestoredFromFileTwice_thenNothingChanges() async throws {
        _ = try await fillSource()
        let (backup, url) = try await verifiedFile(includeSensitive: false)
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await targetService.restore(backup)

        let second = try await targetService.restore(backup)

        #expect(second.restored == 0 && second.alreadyHad == 2)
    }

    @Test("a deletion in the backup removes the clip here before any clip is restored")
    func whenFileHoldsADeletion_thenTheClipIsRemoved() async throws {
        _ = try await fillSource()
        try await ingest("deleted on purpose", minutesAgo: 5, into: targetService)
        let present = try #require(items(in: target).first { $0.displayPreviewText == "deleted on purpose" })
        let tombstone = try BackupRecord.tombstone(BackupTombstoneMetadata(id: present.id, deletedAt: base))
        let data = try BackupFile.write(
            records: [tombstone], origin: BackupOrigin(sequence: 1, deviceID: "test", createdAt: base),
            key: BackupKey.generate(), passphrase: "p", iterations: 1000
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("restore-\(UUID().uuidString)")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let summary = try await targetService.restore(BackupFile.verify(url: url, credential: .passphrase("p")))

        #expect(summary.removedByTombstone == 1)
        #expect(try items(in: target).contains { $0.id == present.id } == false)
    }

    @Test("a restored history has the same clips, titles, notes, tags, pin, collection, shortcut and times")
    func whenRestored_thenCuratedClipIsIdentical() async throws {
        let planID = try await fillSource()

        let summary = try await targetService.restore(roundTrip(includeSensitive: false))

        let restored = try items(in: target)
        #expect(summary.restored == 2 && summary.failed == 0)
        let plan = try #require(restored.first { $0.id == planID })
        #expect(plan.displayPreviewText == "ship on friday")
        #expect(plan.customTitle == "Plan" && plan.userNote == "check twice")
        #expect(plan.tags == ["ops", "weekly"])
        #expect(plan.isPinned && plan.pinnedHotkeyIndex == 2)
        #expect(plan.timestamp == base.addingTimeInterval(-30 * 60))
        let board = try #require(ModelContext(target).fetch(FetchDescriptor<Pinboard>()).first)
        #expect(board.name == "Ship" && plan.collectionID == board.id)
        #expect(plan.blob?.decryptedText() == "ship on friday")
    }

    @Test("clips that hold secrets are left out unless asked for, and come back masked when asked for")
    func whenSensitive_thenOptInAndStillMasked() async throws {
        _ = try await fillSource()

        let without = try await sourceService.backupRecords(includeSensitive: false)
        #expect(without.summary.skippedSensitive == 1)
        _ = try await targetService.restore(roundTrip(includeSensitive: false))
        #expect(try items(in: target).allSatisfy { $0.sensitivity == nil })

        _ = try await targetService.restore(roundTrip(includeSensitive: true))
        let card = try #require(items(in: target).first { $0.sensitivity != nil })
        #expect(card.gridPreview != "4111 1111 1111 1111", "a restored secret is masked like a live one")
    }

    @Test("restoring twice adds nothing and does not reorder what is already there")
    func whenRestoredTwice_thenNothingChanges() async throws {
        _ = try await fillSource()
        let contents = try await roundTrip(includeSensitive: false)
        _ = try await targetService.restore(contents)
        let before = try items(in: target).map { ($0.id, $0.timestamp) }

        let second = try await targetService.restore(contents)

        #expect(second.restored == 0 && second.alreadyHad == 2)
        let after = try items(in: target).map { ($0.id, $0.timestamp) }
        #expect(after.map(\.0) == before.map(\.0) && after.map(\.1) == before.map(\.1))
    }

    @Test("a clip deleted on purpose here is not brought back by an older backup")
    func whenTombstoned_thenNotResurrected() async throws {
        _ = try await fillSource()
        let contents = try await roundTrip(includeSensitive: false)
        try await ingest("only in the backup", minutesAgo: 1)
        let extra = try #require(items(in: source).first { $0.displayPreviewText == "only in the backup" })
        let withExtra = try BackupContents(
            manifest: contents.manifest,
            records: contents.records + [BackupRecord.item(
                BackupItemMetadata(
                    id: extra.id, timestamp: extra.timestamp, typeRaw: "text", mimeType: "public.utf8-plain-text",
                    plainHash: "x"
                ),
                payload: Data("only in the backup".utf8)
            )]
        )
        _ = try await targetService.restore(withExtra)
        let restoredExtra = try #require(items(in: target).first { $0.id == extra.id })
        _ = try await targetService.deleteItems(ids: [restoredExtra.id], reason: .user)

        let again = try await targetService.restore(withExtra)

        #expect(again.keptDeleted == 1)
        #expect(try items(in: target).contains { $0.id == extra.id } == false)
    }

    @Test("a deletion recorded in a newer backup removes the clip from a Mac that restored it earlier")
    func whenBackupHasTombstone_thenLocalCopyGoes() async throws {
        try await ingest("to be removed", minutesAgo: 5)
        _ = try await targetService.restore(roundTrip(includeSensitive: false))
        let removed = try #require(items(in: source).first)
        #expect(try items(in: target).count == 1)
        _ = try await sourceService.deleteItems(ids: [removed.id], reason: .user)

        let summary = try await targetService.restore(roundTrip(includeSensitive: false))

        #expect(summary.removedByTombstone == 1)
        #expect(try items(in: target).isEmpty)
    }

    @Test("a clip larger than the limit is left out and counted, and the rest are kept")
    func whenClipExceedsTheLimit_thenSkippedAndCounted() async throws {
        try await ingest("small", minutesAgo: 3)
        try await ingest(String(repeating: "long text ", count: 400), minutesAgo: 2)

        let export = try await sourceService.backupRecords(includeSensitive: false, maxItemBytes: 1000)

        #expect(export.summary.items == 1)
        #expect(export.summary.skippedTooLarge == 1)
    }

    @Test("clips removed by Clear Everything come back from a backup, because Clear Everything leaves no tombstones")
    func whenEverythingWasCleared_thenARestoreBringsTheClipsBack() async throws {
        _ = try await fillSource()
        let contents = try await roundTrip(includeSensitive: true)
        let before = try items(in: source).count

        try await sourceService.clearEverything()
        #expect(try items(in: source).isEmpty)
        let summary = try await sourceService.restore(contents)

        #expect(summary.keptDeleted == 0)
        #expect(try items(in: source).count == before, "everything is back, and the clip deleted on purpose stays gone")
    }

    @Test("a backup does not carry tombstones older than a year")
    func whenTombstoneIsOld_thenItIsNotExported() async throws {
        let context = ModelContext(source)
        context.insert(DeletedItemTombstone(id: UUID(), deletedAt: Date.now.addingTimeInterval(-400 * 86_400)))
        let recent = UUID()
        context.insert(DeletedItemTombstone(id: recent, deletedAt: .now))
        try context.save()

        let export = try await sourceService.backupRecords(includeSensitive: true)

        #expect(export.summary.tombstones == 1)
    }

    @Test("a kept password-manager copy is never written to a backup, even with secrets included")
    func whenCredentialClip_thenNotInTheBackup() async throws {
        let secret = "swordfish"
        let payload = Data(secret.utf8)
        try await sourceService.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: payload, payloadString: secret,
            frontmostBundleID: "com.1password.1password", timestamp: base,
            contentHash: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined(), isConcealed: true
        ))
        #expect(try #require(items(in: source).first).sensitivity == .credential)
        try await ingest("an ordinary clip", minutesAgo: 1)

        let export = try await sourceService.backupRecords(includeSensitive: true)

        #expect(export.summary.items == 1, "only the ordinary clip is written")
        #expect(export.summary.skippedSensitive == 1)
        _ = try await targetService.restore(roundTrip(includeSensitive: true))
        #expect(try items(in: target).allSatisfy { $0.sensitivity != .credential })
        #expect(try items(in: target).count == 1)
    }

    @Test("a secret that is not a password-manager copy still comes back hidden when secrets are included")
    func whenApiKeyRestored_thenStillHidden() async throws {
        let secret = "sk-live-4eC39HqLyjWDarjtT1zdp7dc"
        try await ingest(secret, minutesAgo: 2)
        let original = try #require(items(in: source).first)
        try #require(original.sensitivity != nil)

        _ = try await targetService.restore(roundTrip(includeSensitive: true))

        let restored = try #require(items(in: target).first)
        #expect(restored.sensitivity == original.sensitivity)
        #expect(restored.gridPreview != secret)
        #expect(restored.blob?.decryptedText() == secret)
    }

    @Test("a restored clip keeps its exact text; this Mac's paste rules do not rewrite it")
    func whenRulesAreOn_thenRestoredTextIsUnchanged() async throws {
        let noRules = ClipboardRules(
            stripTrackingParameters: false, trimWhitespace: false, normalizeLineEndings: false,
            removeDuplicateSpaces: false
        )
        await sourceService.updateRules(noRules)
        await targetService.updateRules(ClipboardRules(stripTrackingParameters: true))
        let url = "https://example.com/page?utm_source=news&id=7"
        try await ingest(url, minutesAgo: 3)

        _ = try await targetService.restore(roundTrip(includeSensitive: true))

        let restored = try #require(items(in: target).first)
        #expect(restored.blob?.decryptedText() == url)
    }

    @Test("streaming the export gives the same summary and records as collecting it, and yields between batches")
    func whenStreamed_thenSameRecordsAsCollected() async throws {
        _ = try await fillSource()
        let collected = try await sourceService.backupRecords(includeSensitive: false)
        let streamed = Mutex<[BackupRecord]>([])

        let summary = try await sourceService.streamBackupRecords(includeSensitive: false, batchSize: 1) { record in
            streamed.withLock { $0.append(record) }
        }

        #expect(summary == collected.summary)
        #expect(streamed.withLock { $0 } == collected.records)
    }

    private static let metadataDecoder = JSONDecoder()

    @Test("a clip copied again while the export runs moves to the end of the list, and nothing is skipped")
    func whenAClipIsRecopiedMidExport_thenNoClipIsMissing() async throws {
        for index in 0..<120 {
            try await ingest("clip \(index)", minutesAgo: Double(1000 - index))
        }
        let container = source
        let moved = Mutex(false)
        let exported = Mutex<[UUID]>([])

        _ = try await sourceService.streamBackupRecords(includeSensitive: false, batchSize: 50) { record in
            if record.kind == .item {
                do {
                    let metadata = try Self.metadataDecoder.decode(BackupItemMetadata.self, from: record.metadata)
                    exported.withLock { $0.append(metadata.id) }
                } catch {
                    Issue.record("cannot read an exported record: \(error)")
                }
            }
            guard !moved.withLock({ let was = $0
                $0 = true
                return was }) else { return }
            let context = ModelContext(container)
            var oldest = FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp)])
            oldest.fetchLimit = 1
            if let first = try? context.fetch(oldest).first {
                first.timestamp = Date(timeIntervalSince1970: 1_900_000_000)
                try? context.save()
            }
        }

        let stored = try Set(items(in: source).map(\.id))
        let ids = exported.withLock { $0 }
        #expect(ids.count >= 120, "exported \(ids.count) records for \(stored.count) clips")
        #expect(stored.isSubset(of: Set(ids)), "a clip is missing from the export")
    }
}
