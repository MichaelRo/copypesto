// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData

enum SyncOutboxRow { case item, collection, tombstone }

/// What is waiting to be written to this Mac's log, and which rows to settle once it has been.
public struct SyncOutbox: Sendable {
    /// Records with `sequence` 0; the transport numbers them as it writes the segment.
    public var records: [SyncRecord] = []
    /// Payloads too big for a record, by `blobName`: the transport seals each into a file beside the log.
    public var blobs: [String: Data] = [:]
    var settled: [Settled] = []

    struct Settled {
        var row: SyncOutboxRow
        var id: UUID
        var stamp: String
        var sent = false
    }

    public var isEmpty: Bool {
        records.isEmpty && settled.isEmpty
    }
}

public extension StorageService {
    /// Payloads up to this size travel inside the log; bigger ones are named files beside it (`blobName`).
    static let inlinePayloadLimit = 256 * 1024

    enum RestampScope {
        /// Everything is sent again (a new key, a first announcement, a new device id). A Mac may only write records
        /// stamped with its own id, so a clip with no stamp or one from another Mac gets a new stamp here, and a clip
        /// this Mac stamped keeps its own: nothing it last changed is overridden.
        case notFrom(deviceID: String)
        /// Clips that hold secrets get a fresh stamp and are sent again: the person changed what may leave this Mac,
        /// and a stamp later than any withdrawal is what lets a clip come back. Everything else is left alone.
        case sensitive
    }

    @discardableResult
    func restampForSync(_ scope: RestampScope) async throws -> Int {
        guard let clock = SyncJournal.clock(for: modelContainer) else { return 0 }
        var count = 0
        func isMine(_ encoded: String?, _ deviceID: String) -> Bool {
            encoded.flatMap(SyncStamp.init(encoded:))?.deviceID == deviceID
        }
        try await forEachClip { item in
            switch scope {
            case let .notFrom(deviceID):
                if !isMine(item.changeClock, deviceID) {
                    item.syncFingerprint = item.syncFingerprintValue()
                    item.changeClock = clock.next().encoded
                }
            case .sensitive:
                guard item.sensitivityRaw != nil else { return }
                item.syncFingerprint = item.syncFingerprintValue()
                item.changeClock = clock.next().encoded
            }
            item.syncDirty = true
            count += 1
        }
        if case let .notFrom(deviceID) = scope {
            for board in try modelContext.fetch(FetchDescriptor<Pinboard>()) {
                if !isMine(board.changeClock, deviceID) {
                    board.syncFingerprint = board.syncFingerprintValue()
                    board.changeClock = clock.next().encoded
                }
                board.syncDirty = true
                count += 1
            }
        }
        try saveOrRollback()
        return count
    }

    /// Builds the records for what changed since the last write. A clip that has not been judged yet waits; one that
    /// must stay here is skipped, or withdrawn if it already went.
    func buildOutbox(includeSensitive: Bool, syncKey: SyncKey, limit: Int = 200) throws -> SyncOutbox {
        var outbox = SyncOutbox()
        guard let clock = SyncJournal.clock(for: modelContainer) else { return outbox }
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.syncDirty == true })
        descriptor.fetchLimit = limit
        for item in try modelContext.fetch(descriptor) {
            try addItem(item, to: &outbox, clock: clock, includeSensitive: includeSensitive, syncKey: syncKey)
        }
        try addCollections(to: &outbox)
        try addTombstones(to: &outbox)
        try saveOrRollback()
        return outbox
    }

    private func addItem(
        _ item: ClipboardItem, to outbox: inout SyncOutbox, clock: SyncClock, includeSensitive: Bool, syncKey: SyncKey
    ) throws {
        guard let stamp = item.changeClock.flatMap(SyncStamp.init(encoded:)) else { return }
        switch SyncEligibility.verdict(for: item, includeSensitive: includeSensitive) {
        case .waitForJudgment:
            return
        case .staysHere:
            if SyncEligibility.needsWithdrawal(item, includeSensitive: includeSensitive) {
                let hash = item.blob?.decryptedData().map { Data(SHA256.hash(data: $0)).hexString }
                let body = SyncTombstoneRecord(id: item.id, kind: .item, plainHash: hash)
                try outbox.records.append(SyncRecord(
                    kind: .tombstone, sequence: 0, stamp: clock.next(), metadata: SyncRecord.encode(body)
                ))
                item.syncEmittedClock = nil
            }
            outbox.settled.append(.init(row: .item, id: item.id, stamp: stamp.encoded))
        case .send:
            guard let (record, external) = try itemRecord(item, stamp: stamp, syncKey: syncKey) else { return }
            outbox.records.append(record)
            if let external { outbox.blobs[external.name] = external.data }
            outbox.settled.append(.init(row: .item, id: item.id, stamp: stamp.encoded, sent: true))
        }
    }

    private func addCollections(to outbox: inout SyncOutbox) throws {
        for board in try modelContext.fetch(FetchDescriptor<Pinboard>(predicate: #Predicate { $0.syncDirty == true })) {
            guard let stamp = board.changeClock.flatMap(SyncStamp.init(encoded:)) else { continue }
            let body = SyncCollectionRecord(
                id: board.id, name: board.name, symbolName: board.symbolName, colorHex: board.colorHex,
                sortOrder: board.sortOrder, isSmart: board.isSmart, smartPredicateData: board.smartPredicateData,
                schemaVersion: board.schemaVersion, triggerBundleID: board.triggerBundleID
            )
            try outbox.records.append(SyncRecord(
                kind: .collection, sequence: 0, stamp: stamp, metadata: SyncRecord.encode(body)
            ))
            outbox.settled.append(.init(row: .collection, id: board.id, stamp: stamp.encoded))
        }
    }

    private func addTombstones(to outbox: inout SyncOutbox) throws {
        let rows = try modelContext.fetch(FetchDescriptor<DeletedItemTombstone>(
            predicate: #Predicate { $0.syncDirty == true }
        ))
        for row in rows {
            guard let stamp = row.changeClock.flatMap(SyncStamp.init(encoded:)) else { continue }
            let body = SyncTombstoneRecord(
                id: row.id, kind: row.kindRaw == "collection" ? .collection : .item, plainHash: row.plainHash
            )
            try outbox.records.append(SyncRecord(
                kind: .tombstone, sequence: 0, stamp: stamp, metadata: SyncRecord.encode(body)
            ))
            outbox.settled.append(.init(row: .tombstone, id: row.id, stamp: stamp.encoded))
        }
    }

    private func itemRecord(_ item: ClipboardItem, stamp: SyncStamp, syncKey: SyncKey) throws
    -> (SyncRecord, (name: String, data: Data)?)? {
        guard let blob = item.blob, let payload = blob.decryptedData() else { return nil }
        var meta = SyncItemRecord(
            id: item.id, plainHash: Data(SHA256.hash(data: payload)).hexString, mimeType: blob.mimeType,
            timestamp: item.timestamp
        )
        meta.sourceBundleID = item.sourceBundleID
        meta.sourceAppName = item.sourceAppName
        meta.isRemote = item.isRemote
        let metadata = item.metadata
        meta.curation.customTitle = metadata.customTitle
        meta.curation.userNote = metadata.userNote
        meta.curation.tags = metadata.tags
        meta.curation.customSymbolName = metadata.customSymbolName
        meta.curation.collectionOrder = metadata.collectionOrder
        meta.curation.collectionID = item.collectionID
        meta.curation.isPinned = item.isPinned
        meta.curation.expiresAt = item.expiresAt
        var body = Data()
        var external: (name: String, data: Data)?
        if payload.count > Self.inlinePayloadLimit {
            let name = syncKey.blobName(plainHash: meta.plainHash)
            meta.blobName = name
            external = (name, payload)
        } else {
            body = payload
        }
        let record = try SyncRecord(
            kind: .item,
            sequence: 0,
            stamp: stamp,
            metadata: SyncRecord.encode(meta),
            payload: body
        )
        return (record, external)
    }

    /// Settles what the transport wrote: a row whose stamp is still the one that was written is clean now. A row that
    /// changed again meanwhile stays dirty and goes out next time.
    func commitOutbox(_ outbox: SyncOutbox) throws {
        for entry in outbox.settled {
            let id = entry.id
            switch entry.row {
            case .item:
                var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
                descriptor.fetchLimit = 1
                guard let item = try modelContext.fetch(descriptor).first,
                      item.changeClock == entry.stamp else { continue }
                item.syncDirty = false
                if entry.sent { item.syncEmittedClock = entry.stamp }
            case .collection:
                var descriptor = FetchDescriptor<Pinboard>(predicate: #Predicate { $0.id == id })
                descriptor.fetchLimit = 1
                guard let board = try modelContext.fetch(descriptor).first,
                      board.changeClock == entry.stamp else { continue }
                board.syncDirty = false
            case .tombstone:
                var descriptor = FetchDescriptor<DeletedItemTombstone>(predicate: #Predicate { $0.id == id })
                descriptor.fetchLimit = 1
                guard let row = try modelContext.fetch(descriptor).first,
                      row.changeClock == entry.stamp else { continue }
                row.syncDirty = false
            }
        }
        try saveOrRollback()
    }
}
