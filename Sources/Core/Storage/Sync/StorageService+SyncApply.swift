// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData

public struct SyncApplySummary: Equatable, Sendable {
    public var added = 0
    public var updated = 0
    public var removed = 0
    public var folded = 0
    public var ignored = 0
    public var failed = 0

    public init() {}
}

extension StorageService {
    /// Applies what other Macs wrote, oldest stamp first, through the same `ingest` a restore uses (so sealing, masking
    /// and classification are the Mac's own). Each record is a whole statement with a stamp: the later stamp wins per
    /// clip and per collection, a deletion beats an older edit and loses to a later one, and two clips with the same
    /// text fold into the one with the earliest stamp. Applying a record twice, or in any order, ends in the same
    /// place.
    /// `blob` reads a payload that is a file beside the log. Saves made here keep the remote stamps.
    public func applySync(_ records: [SyncRecord], blob: @Sendable (String) -> Data? = { _ in
        nil
    }) async throws -> SyncApplySummary {
        var summary = SyncApplySummary()
        let clock = SyncJournal.clock(for: modelContainer)
        try await SyncJournal.$isApplyingRemote.withValue(true) {
            for record in records.sorted(by: { $0.stamp < $1.stamp }) {
                do { try clock?.observe(record.stamp) } catch {
                    summary.failed += 1
                    continue
                }
                switch record.kind {
                case .item: try await applyItem(record, blob: blob, summary: &summary)
                case .tombstone: try applyTombstone(record, summary: &summary)
                case .collection: try applyCollection(record, summary: &summary)
                case .curation, .pasteCounts, .enroll, .rekey: summary.ignored += 1
                }
            }
        }
        return summary
    }

    private func stamp(_ encoded: String?) -> SyncStamp {
        encoded.flatMap(SyncStamp.init(encoded:)) ?? .origin
    }

    private func tombstones(id: UUID, plainHash: String?) throws -> [DeletedItemTombstone] {
        var found = try modelContext.fetch(FetchDescriptor<DeletedItemTombstone>(predicate: #Predicate { $0.id == id }))
        if let plainHash {
            found += try modelContext.fetch(FetchDescriptor<DeletedItemTombstone>(
                predicate: #Predicate { $0.plainHash == plainHash && $0.id != id }
            ))
        }
        return found
    }

    private func tombstoneStamp(_ row: DeletedItemTombstone) -> SyncStamp {
        row.changeClock.flatMap(SyncStamp.init(encoded:))
            ?? SyncStamp(wallMillis: SyncStamp.millis(row.deletedAt), counter: 0, deviceID: "")
    }

    private func item(id: UUID) throws -> ClipboardItem? {
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func twins(plainHash: String, except id: UUID) throws -> [ClipboardItem] {
        let forms = ContentHash.candidates(for: plainHash, key: try? encryption.loadOrCreateKey())
        return try modelContext.fetch(FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { forms.contains($0.contentHash) && $0.id != id }
        ))
    }

    private func markApplied(_ item: ClipboardItem, stamp: SyncStamp) {
        item.changeClock = stamp.encoded
        item.syncOrigin = stamp.deviceID
        item.syncFingerprint = item.syncFingerprintValue()
        item.syncDirty = false
        item.syncEmittedClock = stamp.encoded
    }

    private func apply(_ curation: SyncCuration, to item: ClipboardItem) {
        item.customTitle = curation.customTitle
        item.userNote = curation.userNote
        item.tags = curation.tags
        item.customSymbolName = curation.customSymbolName
        item.collectionOrder = curation.collectionOrder
        item.collectionID = curation.collectionID
        item.isPinned = curation.isPinned
        item.expiresAt = curation.expiresAt
    }

    private func curation(of item: ClipboardItem) -> SyncCuration {
        var curation = SyncCuration()
        let metadata = item.metadata
        curation.customTitle = metadata.customTitle
        curation.userNote = metadata.userNote
        curation.tags = metadata.tags
        curation.customSymbolName = metadata.customSymbolName
        curation.collectionOrder = metadata.collectionOrder
        curation.collectionID = item.collectionID
        curation.isPinned = item.isPinned
        curation.expiresAt = item.expiresAt
        return curation
    }

    private func plainHash(of item: ClipboardItem) -> String? {
        item.blob?.decryptedData().map { Data(SHA256.hash(data: $0)).hexString }
    }

    /// A clip is the same clip on every Mac when its text is the same (its plain SHA-256), whatever id each Mac gave
    /// it.
    /// So two Macs that copied the same words never disagree about which one is "the" clip, and an edit or a deletion
    /// of that text is one statement about it. The id in a record is only the id its Mac used; this Mac keeps its own.
    private func applyItem(
        _ record: SyncRecord,
        blob: @Sendable (String) -> Data?,
        summary: inout SyncApplySummary
    ) async throws {
        guard let meta = try? record.decodeMetadata(SyncItemRecord.self) else {
            summary.failed += 1
            return
        }
        let stampR = record.stamp
        let dead = try tombstones(id: meta.id, plainHash: meta.plainHash)
        if dead.contains(where: { tombstoneStamp($0) >= stampR }) {
            summary.ignored += 1
            return
        }
        // A later record undoes this clip's own deletion; a deletion of the same text under another id stays, so an
        // older record of that text cannot come back.
        for row in dead where row.id == meta.id {
            modelContext.delete(row)
        }

        if let same = try twins(plainHash: meta.plainHash, except: UUID()).first {
            guard stampR > stamp(same.changeClock) else {
                summary.ignored += 1
                return
            }
            apply(meta.curation, to: same)
            markApplied(same, stamp: stampR)
            try saveOrRollback()
            summary.updated += 1
            return
        }
        let payload = meta.blobName.flatMap(blob) ?? record.payload
        guard !payload.isEmpty else {
            summary.failed += 1
            return
        }
        if try item(id: meta.id) != nil {
            // The same clip with new text (a snippet edited, text appended): the old text goes, the new text comes.
            try deleteItems(ids: [meta.id], reason: .merged)
            try await insertRemote(meta, payload: payload, stamp: stampR)
            summary.updated += 1
        } else {
            try await insertRemote(meta, payload: payload, stamp: stampR)
            summary.added += 1
        }
    }

    private func insertRemote(_ meta: SyncItemRecord, payload: Data, stamp: SyncStamp) async throws {
        // The two-second echo guard is for a pasteboard that fires twice, not for a clip that has to be put back.
        lastIngestedHash = nil
        let textual: Set = ["public.utf8-plain-text", "public.url", "public.file-url"]
        try await ingest(
            PasteboardCapture(
                typeIdentifier: meta.mimeType, payload: payload,
                payloadString: textual.contains(meta.mimeType) ? String(data: payload, encoding: .utf8) : nil,
                frontmostBundleID: meta.sourceBundleID, timestamp: meta.timestamp, contentHash: meta.plainHash,
                isRemote: meta.isRemote, isConcealed: false
            ),
            preferredItemID: meta.id, rewritesText: false, popsLookalikePicture: false
        )
        guard let inserted = try item(id: meta.id) else { return }
        apply(meta.curation, to: inserted)
        markApplied(inserted, stamp: stamp)
        try saveOrRollback()
    }

    private func applyTombstone(_ record: SyncRecord, summary: inout SyncApplySummary) throws {
        guard let meta = try? record.decodeMetadata(SyncTombstoneRecord.self) else {
            summary.failed += 1
            return
        }
        let stampT = record.stamp
        switch meta.kind {
        case .collection:
            var descriptor = FetchDescriptor<Pinboard>(predicate: #Predicate { $0.id == meta.id })
            descriptor.fetchLimit = 1
            if let board = try modelContext.fetch(descriptor).first, stamp(board.changeClock) <= stampT {
                modelContext.delete(board)
                summary.removed += 1
            }
        case .item:
            if let local = try item(id: meta.id), stamp(local.changeClock) <= stampT {
                try deleteItems(ids: [meta.id], reason: .merged)
                summary.removed += 1
            }
            if let hash = meta.plainHash {
                for twin in try twins(plainHash: hash, except: meta.id) where stamp(twin.changeClock) <= stampT {
                    try deleteItems(ids: [twin.id], reason: .merged)
                    summary.removed += 1
                }
            }
        }
        let known = try tombstones(id: meta.id, plainHash: nil).first
        if let known {
            guard stampT > tombstoneStamp(known) else { return }
            known.changeClock = stampT.encoded
            known.plainHash = meta.plainHash ?? known.plainHash
            known.kindRaw = meta.kind.rawValue
            known.syncDirty = false
        } else {
            let row = DeletedItemTombstone(id: meta.id)
            row.changeClock = stampT.encoded
            row.plainHash = meta.plainHash
            row.kindRaw = meta.kind.rawValue
            row.syncDirty = false
            modelContext.insert(row)
        }
        try saveOrRollback()
    }

    private func applyCollection(_ record: SyncRecord, summary: inout SyncApplySummary) throws {
        guard let meta = try? record.decodeMetadata(SyncCollectionRecord.self) else {
            summary.failed += 1
            return
        }
        let stampR = record.stamp
        let dead = try tombstones(id: meta.id, plainHash: nil)
        if dead.contains(where: { tombstoneStamp($0) >= stampR }) {
            summary.ignored += 1
            return
        }
        for row in dead {
            modelContext.delete(row)
        }
        var descriptor = FetchDescriptor<Pinboard>(predicate: #Predicate { $0.id == meta.id })
        descriptor.fetchLimit = 1
        let board: Pinboard
        if let existing = try modelContext.fetch(descriptor).first {
            guard stampR > stamp(existing.changeClock) else {
                summary.ignored += 1
                return
            }
            board = existing
            summary.updated += 1
        } else {
            board = Pinboard(
                id: meta.id,
                name: meta.name,
                symbolName: meta.symbolName,
                colorHex: meta.colorHex,
                sortOrder: meta.sortOrder
            )
            modelContext.insert(board)
            summary.added += 1
        }
        board.name = meta.name
        board.symbolName = meta.symbolName
        board.colorHex = meta.colorHex
        board.sortOrder = meta.sortOrder
        board.isSmart = meta.isSmart
        board.smartPredicateData = meta.smartPredicateData
        board.schemaVersion = meta.schemaVersion
        board.triggerBundleID = meta.triggerBundleID
        board.changeClock = stampR.encoded
        board.syncOrigin = stampR.deviceID
        board.syncFingerprint = board.syncFingerprintValue()
        board.syncDirty = false
        try saveOrRollback()
    }
}
