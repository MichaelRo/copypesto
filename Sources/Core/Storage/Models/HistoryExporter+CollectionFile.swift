// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import ImageIO
import SwiftData

extension HistoryExporter {
    private enum ExportOutcome {
        case record(HistoryRecord)
        case sensitive
        case tooLarge
        case unreadable
        case fileReference
        case unsharablePicture
    }

    private enum PayloadVerdict {
        case accepted(Data, type: String)
        case tooLarge
        case unreadable
    }

    private static let batchSize = 25
    private static let envelopeAllowance = 1_048_576
    private static let recordOverhead = 700

    /// The collection as a version 2 file: each clip with its original data, except a secret, a hidden clip, a file
    /// clip, one not yet judged and one over `CollectionFilePolicy.maxPayloadBytes`, which are left out and counted, as
    /// are clips past the file's `maxClips` (ADR 0045). The newest clips are kept.
    public func exportCollectionFile(id: UUID) throws -> CollectionExportFile {
        let boards = try modelContext.fetch(FetchDescriptor<Pinboard>())
        guard let board = boards.first(where: { $0.id == id }) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let allItems = try modelContext.fetch(
            FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        )
        var records: [HistoryRecord] = []
        var skippedSensitive = 0
        var skippedTooLarge = 0
        var skippedUnreadable = 0
        var skippedFiles = 0
        var skippedOverLimit = 0
        var skippedPictures = 0
        var estimatedBytes = Self.envelopeAllowance
        for item in allItems where item.collectionID == id {
            if records.count >= CollectionFilePolicy.maxClips {
                skippedOverLimit += 1
                continue
            }
            switch exportOutcome(for: item) {
            case let .record(record):
                let size = Self.estimatedSize(of: record)
                guard estimatedBytes + size <= Self.maxImportBytes - Self.envelopeAllowance else {
                    skippedTooLarge += 1
                    continue
                }
                estimatedBytes += size
                records.append(record)
            case .sensitive: skippedSensitive += 1
            case .tooLarge: skippedTooLarge += 1
            case .unreadable: skippedUnreadable += 1
            case .fileReference: skippedFiles += 1
            case .unsharablePicture: skippedPictures += 1
            }
        }
        let payload = CollectionExportPayload(
            collection: .init(
                id: board.id,
                name: board.name,
                symbolName: board.symbolName,
                colorHex: board.colorHex
            ),
            items: records
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(payload)
        guard data.count <= Self.maxImportBytes else { throw ImportError.fileTooLarge }
        return CollectionExportFile(
            data: data,
            exported: records.count,
            skippedSensitive: skippedSensitive,
            skippedTooLarge: skippedTooLarge,
            skippedUnreadable: skippedUnreadable,
            skippedFiles: skippedFiles,
            skippedOverLimit: skippedOverLimit,
            skippedPictures: skippedPictures
        )
    }

    /// What a record adds to the file, the free text included, so a near-cap export skips a clip instead of failing.
    private static func estimatedSize(of record: HistoryRecord) -> Int {
        let texts = [
            record.payload,
            record.previewText,
            record.customTitle,
            record.userNote,
            record.sourceApp,
            record.sourceBundleID
        ] + record.tags.map(Optional.some)
        return texts.reduce(recordOverhead) { $0 + ($1?.utf8.count ?? 0) * 2 }
    }

    private func exportOutcome(for item: ClipboardItem) -> ExportOutcome {
        if item.sensitivityRaw != nil || item.analysisPending { return .sensitive }
        if item.type == .file { return .fileReference }
        if item.byteSize > CollectionFilePolicy.maxPayloadBytes { return .tooLarge }
        let isTextual = Self.isTextual(item.typeRaw)
        if item.type == .image, let mime = item.blob?.mimeType, !CollectionFilePolicy.isAllowedPayloadType(mime) {
            return .unsharablePicture
        }
        guard let blob = item.blob, let data = blob.decryptedData(),
              CollectionFilePolicy.isAllowedPayloadType(blob.mimeType) else
        {
            return previewOnlyOutcome(for: item, isTextual: isTextual)
        }
        guard data.count <= CollectionFilePolicy.maxPayloadBytes else { return .tooLarge }
        if CollectionFilePolicy.isText(blob.mimeType) {
            guard let text = String(data: data, encoding: .utf8) else { return .unreadable }
            if SensitiveContentDetector.detectAnywhere(in: text) != nil { return .sensitive }
        }
        return .record(record(
            for: item, preview: isTextual ? item.displayPreviewText : "", payload: data, payloadType: blob.mimeType
        ))
    }

    /// A text clip whose data cannot be read still has its preview, as in a version 1 file; any other kind has nothing
    /// to carry.
    private func previewOnlyOutcome(for item: ClipboardItem, isTextual: Bool) -> ExportOutcome {
        let preview = item.displayPreviewText
        guard isTextual, !preview.isEmpty else { return .unreadable }
        return .record(record(for: item, preview: preview, payload: nil, payloadType: nil))
    }

    private func record(for item: ClipboardItem, preview: String, payload: Data?, payloadType: String?)
    -> HistoryRecord {
        HistoryRecord(
            id: item.id,
            timestamp: item.timestamp,
            type: item.typeRaw,
            previewText: preview,
            sourceApp: item.sourceAppName,
            sourceBundleID: item.sourceBundleID,
            customTitle: item.customTitle,
            userNote: item.userNote,
            tags: item.tags,
            isPinned: item.isPinned,
            payload: payload?.base64EncodedString(),
            payloadType: payloadType
        )
    }

    /// A record waiting for its collection and notes, which are written in a fresh context once the background analysis
    /// has finished: this actor's cached copy of the clip would carry the flags from before it did.
    private struct Pending {
        let id: UUID
        let record: HistoryRecord
    }

    /// Records that carry data go through `StorageService.ingest` as a live copy would (ADR 0045): the type is read
    /// from the data, never from the file, the data is sealed under the history key, and a secret in text is masked.
    /// Each record's data is dropped once it is stored, and the ids added so far are in `insertedIDs` whatever happens
    /// next, so a failure part-way still leaves an Undo that covers them.
    func importPayloadRecords(
        _ records: inout [HistoryRecord],
        storage: StorageService,
        exclusionRules: ExclusionRules,
        result: inout CollectionImportResult,
        insertedIDs: inout [UUID]
    ) async throws {
        guard !records.isEmpty else { return }
        let collectionID = result.collectionID
        // A key that cannot be had fails the import: clips are never stored under a plain hash.
        let key = try BlobEncryption().loadOrCreateKey()
        var pending: [Pending] = []
        for index in records.indices {
            var record = records[index]
            records[index].payload = nil
            guard let (data, type) = Self.screened(record, exclusionRules: exclusionRules, result: &result) else {
                continue
            }
            record.payload = nil
            let hash = data.sha256Hex
            let forms = ContentHash.candidates(for: hash, key: key)
            let sameContent = FetchDescriptor<ClipboardItem>(predicate: #Predicate { forms.contains($0.contentHash) })
            if try modelContext.fetchCount(sameContent) > 0 {
                result.alreadyPresent += 1
                continue
            }
            let capture = PasteboardCapture(
                typeIdentifier: type,
                payload: data,
                payloadString: CollectionFilePolicy.isText(type) ? String(data: data, encoding: .utf8) : nil,
                frontmostBundleID: record.sourceBundleID,
                contentHash: hash
            )
            let newID = UUID()
            do {
                try await storage.ingest(
                    capture, preferredItemID: newID, rewritesText: false, popsLookalikePicture: false
                )
            } catch is ClipSizePolicy.TooLarge {
                result.skippedTooLarge += 1
                continue
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                result.skippedUnreadable += 1
                continue
            }
            guard try ModelContext(modelContainer).fetchCount(
                FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == newID })
            ) > 0 else {
                result.alreadyPresent += 1
                continue
            }
            insertedIDs.append(newID)
            pending.append(Pending(id: newID, record: record))
            if pending.count == Self.batchSize {
                await storage.waitForBackgroundWork()
                try flush(&pending, collectionID: collectionID)
            }
        }
        await storage.waitForBackgroundWork()
        try flush(&pending, collectionID: collectionID)
    }

    private func flush(_ pending: inout [Pending], collectionID: UUID) throws {
        defer { pending.removeAll() }
        guard !pending.isEmpty else { return }
        let context = ModelContext(modelContainer)
        for entry in pending {
            let id = entry.id
            guard let item = try context.fetch(
                FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
            ).first else { continue }
            apply(entry.record, to: item, collectionID: collectionID)
        }
        try context.saveOrRollback()
    }

    /// The record's data and type, or nil after counting why it is left out.
    private static func screened(
        _ record: HistoryRecord, exclusionRules: ExclusionRules, result: inout CollectionImportResult
    )
    -> (Data, String)? {
        if record.payloadType == CollectionFilePolicy.fileURLType {
            result.skippedFiles += 1
            return nil
        }
        if let bundleID = record.sourceBundleID, exclusionRules.isExcluded(bundleID) {
            result.skippedSensitive += 1
            return nil
        }
        switch verdict(for: record) {
        case let .accepted(data, type): return (data, type)
        case .tooLarge: result.skippedTooLarge += 1
        case .unreadable: result.skippedUnreadable += 1
        }
        return nil
    }

    private func apply(_ record: HistoryRecord, to item: ClipboardItem, collectionID: UUID) {
        item.collectionID = collectionID
        item.customTitle = record.customTitle
        item.userNote = record.userNote
        item.tags = record.tags
        item.isPinned = record.isPinned
        item.adoptFirstCopy(record.timestamp)
        if item.sourceAppName == nil { item.sourceAppName = record.sourceApp }
    }

    /// Checks one record's data before anything is decoded or stored: a base64 string past the cap is refused by
    /// length alone.
    private static func verdict(for record: HistoryRecord) -> PayloadVerdict {
        guard let encoded = record.payload, let type = record.payloadType,
              CollectionFilePolicy.isAllowedPayloadType(type) else { return .unreadable }
        guard encoded.utf8.count <= CollectionFilePolicy.maxEncodedLength else { return .tooLarge }
        guard let data = Data(base64Encoded: encoded), !data.isEmpty else { return .unreadable }
        guard data.count <= CollectionFilePolicy.maxPayloadBytes else { return .tooLarge }
        if CollectionFilePolicy.isText(type) {
            guard let text = String(data: data, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .unreadable }
        } else if CollectionFilePolicy.isPDF(type) {
            guard CollectionFilePolicy.opensAsPDF(data) else { return .unreadable }
        } else if CollectionFilePolicy.isRaster(type) {
            guard let pixels = pixelCount(of: data) else { return .unreadable }
            guard pixels <= CollectionFilePolicy.maxPixels else { return .tooLarge }
        }
        return .accepted(data, type: type)
    }

    /// The picture's size from its header, without decoding it; nil when ImageIO cannot read it as a picture.
    private static func pixelCount(of data: Data) -> Int? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return width * height
    }
}
