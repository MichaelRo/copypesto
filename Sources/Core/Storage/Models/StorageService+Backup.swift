// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import os
import SwiftData

public struct BackupExportSummary: Sendable, Equatable {
    public var items = 0
    public var collections = 0
    public var tombstones = 0
    public var skippedSensitive = 0
    public var skippedUnreadable = 0
    /// The clips counted in `skippedUnreadable`, so they can be found and removed.
    public var unreadableIDs: [UUID] = []
    public var skippedNoPayload = 0
    public var skippedTooLarge = 0
}

public struct BackupRestoreSummary: Sendable, Equatable {
    public var restored = 0
    public var alreadyHad = 0
    public var keptDeleted = 0
    public var removedByTombstone = 0
    public var collections = 0
    public var failed = 0
}

extension StorageService {
    /// Turns the history into backup records: each clip's payload decrypted with this Mac's key (the backup file seals
    /// it
    /// again under the backup key), with its curation, plus collections and the deletions the user made on purpose.
    /// Clips that hold secrets are left out unless `includeSensitive`; clips larger than `maxItemBytes` are always left
    /// out, so a backup in a synced folder never fills someone's storage with a picture or a long recording.
    public func backupRecords(
        includeSensitive: Bool,
        maxItemBytes: Int = AutoBackupSettings.largestClipBytes
    ) throws
    -> (records: [BackupRecord], summary: BackupExportSummary) {
        var summary = BackupExportSummary()
        var records = try collectionRecords(summary: &summary)
        for item in try modelContext.fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp)])) {
            if let record = try itemRecord(
                item,
                includeSensitive: includeSensitive,
                maxItemBytes: maxItemBytes,
                summary: &summary
            ) {
                records.append(record)
            }
        }
        try records.append(contentsOf: tombstoneRecords(summary: &summary))
        return (records, summary)
    }

    /// The same records, handed to `sink` one at a time in batches that let other work (a new copy being stored) run in
    /// between, so a large history is never all in memory at once and never holds this actor for the whole export.
    public func streamBackupRecords(
        includeSensitive: Bool,
        maxItemBytes: Int = AutoBackupSettings.largestClipBytes,
        batchSize: Int = 50,
        sink: @Sendable (BackupRecord) throws -> Void
    ) async throws
    -> BackupExportSummary {
        var summary = BackupExportSummary()
        for record in try collectionRecords(summary: &summary) {
            try sink(record)
        }
        // Paged by timestamp, not by offset: a re-copy moves an old clip to the end and a delete shifts everything
        // after it, either of which would make an offset skip a clip. The ids already written at the cursor's own
        // timestamp are remembered, because several clips can share one.
        var cursor: Date?
        var written: Set<UUID> = []
        while true {
            var descriptor: FetchDescriptor<ClipboardItem> = if let start = cursor {
                FetchDescriptor(
                    predicate: #Predicate { $0.timestamp >= start }, sortBy: [SortDescriptor(\.timestamp)]
                )
            } else {
                FetchDescriptor(sortBy: [SortDescriptor(\.timestamp)])
            }
            let limit = batchSize + written.count
            descriptor.fetchLimit = limit
            let page = try modelContext.fetch(descriptor)
            let fresh = page.filter { !written.contains($0.id) }
            guard let last = fresh.last else { break }
            for item in fresh {
                if let record = try itemRecord(
                    item,
                    includeSensitive: includeSensitive,
                    maxItemBytes: maxItemBytes,
                    summary: &summary
                ) {
                    try sink(record)
                }
            }
            if last.timestamp != cursor { written = [] }
            written.formUnion(fresh.filter { $0.timestamp == last.timestamp }.map(\.id))
            cursor = last.timestamp
            guard page.count == limit else { break }
            await Task.yield()
        }
        for record in try tombstoneRecords(summary: &summary) {
            try sink(record)
        }
        return summary
    }

    private func collectionRecords(summary: inout BackupExportSummary) throws -> [BackupRecord] {
        var records: [BackupRecord] = []
        for board in try modelContext.fetch(FetchDescriptor<Pinboard>(sortBy: [SortDescriptor(\.sortOrder)])) {
            try records.append(.collection(BackupCollectionMetadata(
                id: board.id, name: board.name, symbolName: board.symbolName, colorHex: board.colorHex,
                sortOrder: board.sortOrder, isSmart: board.isSmart, smartPredicateData: board.smartPredicateData,
                schemaVersion: board.schemaVersion, triggerBundleID: board.triggerBundleID
            )))
            summary.collections += 1
        }
        return records
    }

    private func itemRecord(
        _ item: ClipboardItem, includeSensitive: Bool, maxItemBytes: Int, summary: inout BackupExportSummary
    ) throws
    -> BackupRecord? {
        if item.analysisPending {
            summary.skippedSensitive += 1
            return nil
        }
        let isKeptCredential = item.sensitivityRaw == SensitivityCategory.credential.rawValue
        if item.sensitivityRaw != nil, !includeSensitive || isKeptCredential {
            summary.skippedSensitive += 1
            return nil
        }
        if item.byteSize > maxItemBytes {
            summary.skippedTooLarge += 1
            return nil
        }
        guard let blob = item.blob else {
            summary.skippedNoPayload += 1
            return nil
        }
        guard let payload = blob.decryptedData() else {
            summary.skippedUnreadable += 1
            summary.unreadableIDs.append(item.id)
            return nil
        }
        summary.items += 1
        return try .item(
            BackupItemMetadata(
                id: item.id, timestamp: item.timestamp, typeRaw: item.typeRaw, mimeType: blob.mimeType,
                plainHash: payload.sha256Hex,
                sourceBundleID: item.sourceBundleID, sourceAppName: item.sourceAppName,
                customTitle: item.customTitle, userNote: item.userNote, tags: item.tags, isPinned: item.isPinned,
                collectionID: item.collectionID, pinnedHotkeyIndex: item.pinnedHotkeyIndex,
                expiresAt: item.expiresAt, isNSFW: item.isNSFW, pasteCount: item.pasteCount,
                sensitivityRaw: item.sensitivityRaw, isRemote: item.isRemote,
                shortcutLastUsedAt: item.shortcutLastUsedAt
            ),
            payload: payload
        )
    }

    private func tombstoneRecords(summary: inout BackupExportSummary) throws -> [BackupRecord] {
        let oldest = Date.now.addingTimeInterval(-Self.tombstoneLifetime)
        let kept = try modelContext.fetch(FetchDescriptor<DeletedItemTombstone>(
            predicate: #Predicate { $0.deletedAt >= oldest }
        ))
        var records: [BackupRecord] = []
        for tombstone in kept {
            try records.append(.tombstone(BackupTombstoneMetadata(id: tombstone.id, deletedAt: tombstone.deletedAt)))
            summary.tombstones += 1
        }
        return records
    }

    /// Merges a backup that has already been authenticated into this history. Nothing here overwrites a clip the Mac
    /// already has, nothing is reordered, and a clip deleted on purpose (here or in the backup) does not come back.
    /// Every clip goes through `ingest`, so encryption, masking and classification apply as for a live copy.
    public func restore(_ contents: BackupContents) async throws -> BackupRestoreSummary {
        var summary = BackupRestoreSummary()
        var deleted = try Set(modelContext.fetch(FetchDescriptor<DeletedItemTombstone>()).map(\.id))
        try restoreTombstones(contents.records, deleted: &deleted, summary: &summary)
        let collectionIDs = try restoreCollections(contents.records, summary: &summary)
        try saveOrRollback()
        try await restoreItems(contents.records, deleted: deleted, collectionIDs: collectionIDs, summary: &summary)
        wipeSuggestionLedger?()
        return summary
    }

    /// The same merge, reading the clips from a verified file one at a time instead of holding them all: deletions and
    /// collections first, which are few, then each clip as it is read. Every chunk is authenticated again as it is
    /// read.
    public func restore(_ backup: VerifiedBackup) async throws -> BackupRestoreSummary {
        var summary = BackupRestoreSummary()
        var deleted = try Set(modelContext.fetch(FetchDescriptor<DeletedItemTombstone>()).map(\.id))
        try restoreTombstones(backup.smallRecords, deleted: &deleted, summary: &summary)
        let collectionIDs = try restoreCollections(backup.smallRecords, summary: &summary)
        try saveOrRollback()
        try await backup.forEachItem { record in
            try await restoreItem(record, deleted: deleted, collectionIDs: collectionIDs, summary: &summary)
        }
        wipeSuggestionLedger?()
        return summary
    }

    private func restoreTombstones(
        _ records: [BackupRecord], deleted: inout Set<UUID>, summary: inout BackupRestoreSummary
    ) throws {
        for record in records where record.kind == .tombstone {
            guard let tombstone = try? record.tombstoneMetadata() else { summary.failed += 1
                continue
            }
            if deleted.insert(tombstone.id).inserted {
                modelContext.insert(DeletedItemTombstone(id: tombstone.id, deletedAt: tombstone.deletedAt))
            }
            let present = try modelContext.fetch(FetchDescriptor<ClipboardItem>(
                predicate: #Predicate { $0.id == tombstone.id }
            ))
            if !present.isEmpty {
                _ = try deleteItems(ids: [tombstone.id], reason: .restore)
                summary.removedByTombstone += 1
            }
        }
    }

    private func restoreCollections(
        _ records: [BackupRecord],
        summary: inout BackupRestoreSummary
    ) throws
    -> Set<UUID> {
        var collectionIDs = try Set(modelContext.fetch(FetchDescriptor<Pinboard>()).map(\.id))
        for record in records where record.kind == .collection {
            guard let board = try? record.collectionMetadata() else { summary.failed += 1
                continue
            }
            if collectionIDs.insert(board.id).inserted {
                let created = Pinboard(
                    id: board.id, name: board.name, symbolName: board.symbolName, colorHex: board.colorHex,
                    sortOrder: board.sortOrder, isSmart: board.isSmart
                )
                created.smartPredicateData = board.smartPredicateData
                created.schemaVersion = board.schemaVersion
                created.triggerBundleID = board.triggerBundleID
                modelContext.insert(created)
                summary.collections += 1
            }
        }
        return collectionIDs
    }

    private func restoreItems(
        _ records: [BackupRecord], deleted: Set<UUID>, collectionIDs: Set<UUID>, summary: inout BackupRestoreSummary
    ) async throws {
        for record in records where record.kind == .item {
            try await restoreItem(record, deleted: deleted, collectionIDs: collectionIDs, summary: &summary)
        }
    }

    private func restoreItem(
        _ record: BackupRecord, deleted: Set<UUID>, collectionIDs: Set<UUID>, summary: inout BackupRestoreSummary
    ) async throws {
        guard let meta = try? record.itemMetadata() else {
            summary.failed += 1
            return
        }
        if deleted.contains(meta.id) {
            summary.keptDeleted += 1
            return
        }
        if try alreadyHas(itemID: meta.id, plainHash: meta.plainHash) {
            summary.alreadyHad += 1
            return
        }
        let itemID = meta.id
        do {
            try await ingest(
                Self.capture(from: meta, payload: record.payload), preferredItemID: meta.id, rewritesText: false,
                popsLookalikePicture: false
            )
            // A picture that looks like one already here is not stored: it is not a restored clip.
            guard try modelContext.fetchCount(FetchDescriptor<ClipboardItem>(
                predicate: #Predicate { $0.id == itemID }
            )) > 0 else {
                summary.alreadyHad += 1
                return
            }
            try applyCuration(of: meta, collectionIDs: collectionIDs)
            summary.restored += 1
        } catch {
            // Counted, and the reason logged: a full disk or a locked store looks like "N clips failed" otherwise.
            Self.restoreLogger.error("Restoring a clip failed: \(error.localizedDescription, privacy: .public)")
            summary.failed += 1
        }
    }

    private static let restoreLogger = Logger(subsystem: AppIdentity.logSubsystem, category: "BackupRestore")

    func alreadyHas(itemID: UUID, plainHash: String) throws -> Bool {
        let forms = ContentHash.candidates(for: plainHash, key: try? encryption.loadOrCreateKey())
        let byID = try modelContext
            .fetchCount(FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == itemID }))
        let byHash = try modelContext.fetchCount(FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { forms.contains($0.contentHash) }
        ))
        return byID > 0 || byHash > 0
    }

    private static func capture(from meta: BackupItemMetadata, payload: Data) -> PasteboardCapture {
        let textual: Set = ["public.utf8-plain-text", "public.url", "public.file-url"]
        return PasteboardCapture(
            typeIdentifier: meta.mimeType, payload: payload,
            payloadString: textual.contains(meta.mimeType) ? String(data: payload, encoding: .utf8) : nil,
            frontmostBundleID: meta.sourceBundleID, timestamp: meta.timestamp, contentHash: meta.plainHash,
            isRemote: meta.isRemote == true, isConcealed: meta.sensitivityRaw == SensitivityCategory.credential.rawValue
        )
    }

    private func applyCuration(of meta: BackupItemMetadata, collectionIDs: Set<UUID>) throws {
        let id = meta.id
        guard let item = try modelContext.fetch(FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id }))
            .first else { return }
        item.customTitle = meta.customTitle
        item.userNote = meta.userNote
        item.tags = meta.tags
        item.isPinned = meta.isPinned
        item.expiresAt = meta.expiresAt
        item.pasteCount = meta.pasteCount
        if meta.isNSFW { item.isNSFW = true }
        if let board = meta.collectionID, collectionIDs.contains(board) { item.collectionID = board }
        if let slot = meta.pinnedHotkeyIndex, try !slotIsTaken(slot) {
            item.pinnedHotkeyIndex = slot
            item.shortcutLastUsedAt = meta.shortcutLastUsedAt
        }
        try saveOrRollback()
    }

    private func slotIsTaken(_ slot: Int) throws -> Bool {
        try modelContext
            .fetchCount(FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.pinnedHotkeyIndex == slot })) > 0
    }
}
