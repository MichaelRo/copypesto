// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData

/// JSON export/import for clipboard history.
/// Export format: array of HistoryRecord objects: previews only. A collection file (version 2) adds each clip's data.
@ModelActor
public actor HistoryExporter {
    public struct HistoryRecord: Codable, Sendable {
        public let id: UUID
        public let timestamp: Date
        public let type: String
        public let previewText: String
        public let sourceApp: String?
        public let sourceBundleID: String?
        public let customTitle: String?
        public let userNote: String?
        public let tags: [String]
        public let isPinned: Bool
        /// Version 2: the clip's original data as base64, and the type identifier it was stored under.
        public var payload: String?
        public var payloadType: String?
    }

    /// The kinds a text export carries. A picture's preview is the text read out of it and a file's is its full path,
    /// neither of which the person expects in a file of "text previews"; an imported one would be a card with no
    /// payload.
    private static let textualTypes: Set<ClipboardType> = [.text, .code, .url, .color]

    static func isTextual(_ rawType: String) -> Bool {
        ClipboardType(rawValue: rawType).map(textualTypes.contains) ?? true
    }

    public func export() throws -> Data {
        let descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let items = try modelContext.fetch(descriptor).filter { Self.isTextual($0.typeRaw) }
        let records = items.map { item in
            HistoryRecord(
                id: item.id,
                timestamp: item.timestamp,
                type: item.typeRaw,
                previewText: item.displayPreviewText,
                sourceApp: item.sourceAppName,
                sourceBundleID: item.sourceBundleID,
                customTitle: item.customTitle,
                userNote: item.userNote,
                tags: item.tags,
                isPinned: item.isPinned
            )
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(records)
    }

    /// The text as a sealed blob, so an imported clip pastes whole and is part of every backup like any other clip.
    private func textBlob(for item: ClipboardItem) -> ClipboardBlob? {
        guard item.type == .text || item.type == .code, item.sensitivityRaw == nil else { return nil }
        let text = item.displayPreviewText
        guard !text.isEmpty,
              let envelope = try? BlobEncryption().encrypt(
                  Data(text.utf8), associatedData: BlobEncryption.associatedData(itemID: item.id, field: .blob)
              ) else { return nil }
        let blob = ClipboardBlob(
            encryptedData: envelope.ciphertext, nonceData: envelope.nonce, mimeType: "public.utf8-plain-text"
        )
        blob.aadBound = true
        return blob
    }

    /// Matches the watcher's hash of a text payload, so an imported item dedupes against a live copy.
    static func contentHash(of text: String) -> String {
        Data(text.utf8).sha256Hex
    }

    /// Most records one file may carry, longest preview one record may hold, and biggest file read at all. An export
    /// holds previews of at most 500 characters, so anything past these is not a Pesto export (R-02, R-07).
    public static let maxRecords = 50_000
    public static let maxRecordCharacters = 2000
    public static let maxImportBytes = 64 * 1_048_576

    public enum ImportError: Error, Sendable, Equatable {
        case fileTooLarge
        case tooManyRecords
        case unsupportedVersion
        case notARegularFile
    }

    private var sealPreview: @Sendable (Data, UUID) throws -> BlobEncryption.EncryptedEnvelope = { data, id in
        try BlobEncryption().encrypt(data, associatedData: BlobEncryption.associatedData(itemID: id, field: .preview))
    }

    func useSealer(_ sealer: @escaping @Sendable (Data, UUID) throws -> BlobEncryption.EncryptedEnvelope) {
        sealPreview = sealer
    }

    /// Reads an import file: a regular file only, refused over `maxImportBytes` before any of it is loaded.
    static func boundedContents(of url: URL) throws -> Data {
        try CollectionFileReader.read(url, maxBytes: maxImportBytes)
    }

    private static func decodeRecords(_ data: Data) throws -> [HistoryRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([HistoryRecord].self, from: data)
    }

    /// Imports records, skipping any whose `id` already exists in the store.
    /// Returns the count of newly inserted items.
    @discardableResult
    public func importRecords(from data: Data) throws -> Int {
        let records = try Self.decodeRecords(data)
        guard records.count <= Self.maxRecords else { throw ImportError.tooManyRecords }
        var result = CollectionImportResult(collectionID: UUID())
        let inserted = try insertNew(records, collectionID: nil, result: &result).count
        if inserted > 0 { try modelContext.saveOrRollback() }
        return inserted
    }

    @discardableResult
    public func importRecords(fromFile url: URL) throws -> Int {
        try importRecords(from: Self.boundedContents(of: url))
    }

    public struct CollectionMetadata: Codable, Sendable {
        public let id: UUID
        public let name: String
        public let symbolName: String
        public let colorHex: String
        public let isSmart: Bool
        public let smartPredicateData: Data?

        public init(
            id: UUID = UUID(),
            name: String,
            symbolName: String,
            colorHex: String,
            isSmart: Bool = false,
            smartPredicateData: Data? = nil
        ) {
            self.id = id
            self.name = name
            self.symbolName = symbolName
            self.colorHex = colorHex
            self.isSmart = isSmart
            self.smartPredicateData = smartPredicateData
        }
    }

    public struct CollectionExportPayload: Codable, Sendable {
        public let version: Int
        public let collection: CollectionMetadata
        public let items: [HistoryRecord]

        public init(
            version: Int = CollectionFilePolicy.currentVersion,
            collection: CollectionMetadata,
            items: [HistoryRecord]
        ) {
            self.version = version
            self.collection = collection
            self.items = items
        }
    }

    /// The file's clips as the older, text-only file would hold them: one call for a caller that wants just the bytes.
    public func exportCollection(id: UUID) throws -> Data {
        try exportCollectionFile(id: id).data
    }

    /// The collection as a file at `url`, written whole or not at all, so a failed export never leaves half a file.
    @discardableResult
    public func writeCollection(id: UUID, to url: URL) throws -> CollectionExportFile {
        let file = try exportCollectionFile(id: id)
        try PrivateFile.write(file.data, to: url)
        return file
    }

    @discardableResult
    public func importCollection(
        fromFile url: URL, storage: StorageService, exclusionRules: ExclusionRules = ExclusionRules(),
        undoHistory: UndoHistory? = nil
    ) async throws
    -> CollectionImportResult {
        // The file's bytes end with this expression: only the decoded records are alive while clips are added.
        let payload = try Self.decodeCollection(Self.boundedContents(of: url))
        return try await importCollection(
            payload,
            storage: storage,
            exclusionRules: exclusionRules,
            undoHistory: undoHistory
        )
    }

    @discardableResult
    public func importCollection(
        from data: Data, storage: StorageService, exclusionRules: ExclusionRules = ExclusionRules(),
        undoHistory: UndoHistory? = nil
    ) async throws
    -> CollectionImportResult {
        let payload = try Self.decodeCollection(data)
        return try await importCollection(
            payload,
            storage: storage,
            exclusionRules: exclusionRules,
            undoHistory: undoHistory
        )
    }

    /// What the person is asked before a file is imported: the collection's name, how many clips can come in, and how
    /// many of their oldest unpinned clips the retention limit would then remove (an upper bound: a clip already in the
    /// history is not added). Runs on this actor, off the main thread.
    public func importPreview(fromFile url: URL, policy: RetentionPolicy) throws -> CollectionImportPreview {
        let summary = try CollectionFileType.summary(ofFile: url)
        let unpinned = try modelContext
            .fetchCount(FetchDescriptor<ClipboardItem>(predicate: #Predicate { !$0.isPinned }))
        let over = unpinned + summary.importableUnpinnedCount - policy.maxItemCount
        return CollectionImportPreview(
            name: summary.name,
            importableCount: summary.importableCount,
            wouldRemove: max(0, min(over, unpinned)),
            limit: policy.maxItemCount
        )
    }

    static func decodeCollection(_ data: Data) throws -> CollectionExportPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(CollectionExportPayload.self, from: data)
        guard payload.version <= CollectionFilePolicy.currentVersion else { throw ImportError.unsupportedVersion }
        guard payload.items.count <= CollectionFilePolicy.maxClips else { throw ImportError.tooManyRecords }
        return payload
    }

    /// Adds a collection file's clips to the collection of the same name, or to a new one. Nothing from the file's ids
    /// is kept: clips and the collection get new ids, and a clip the history already holds (by content) is not added
    /// twice. A clip with a payload goes through `StorageService.ingest` like a live copy (ADR 0045); one without (a
    /// version 1 file) takes the text-only path. With an `undoHistory` the import is one action that Undo takes back.
    private func importCollection(
        _ payload: CollectionExportPayload, storage: StorageService, exclusionRules: ExclusionRules,
        undoHistory: UndoHistory?
    ) async throws
    -> CollectionImportResult {
        let name = CollectionFilePolicy.sanitizedName(payload.collection.name)
        let boardName = name.isEmpty ? CollectionFilePolicy.defaultName : name
        let existingBoards = try modelContext.fetch(FetchDescriptor<Pinboard>())
        let targetBoard: Pinboard
        var createdBoard: PinboardSnapshot?
        if let existing = existingBoards.first(where: { $0.name == boardName }) {
            targetBoard = existing
        } else {
            let newBoard = Pinboard(
                name: boardName,
                symbolName: CollectionFilePolicy.validSymbol(payload.collection.symbolName),
                colorHex: CollectionFilePolicy.validColor(payload.collection.colorHex)
                    ?? CollectionPalette.nextUnused(used: existingBoards.map(\.colorHex)),
                sortOrder: (existingBoards.map(\.sortOrder).max() ?? 0) + 1
            )
            modelContext.insert(newBoard)
            targetBoard = newBoard
            createdBoard = PinboardSnapshot(newBoard)
        }

        var result = CollectionImportResult(collectionID: targetBoard.id, collectionName: boardName)
        var insertedIDs: [UUID] = []
        func commit() throws {
            let changedSomething = !insertedIDs.isEmpty || createdBoard != nil
            if changedSomething { try modelContext.saveOrRollback() }
            if let undoHistory, !insertedIDs.isEmpty || createdBoard != nil,
               insertedIDs.count <= UndoPolicy.maxClipsPerEntry
            {
                let added = AddedClips(kind: .collection, ids: insertedIDs, boards: createdBoard.map { [$0] } ?? [])
                undoHistory.record(UndoEntry(.clipsAdded(added)))
            }
        }
        // Oldest first, so the file's newest clip is the newest in the history.
        var records = payload.items.sorted { $0.timestamp < $1.timestamp }
        do {
            try insertText(
                records.filter { $0.payload == nil }, collectionID: targetBoard.id, mintsIDs: true,
                result: &result, insertedIDs: &insertedIDs
            )
            records.removeAll { $0.payload == nil }
            try await importPayloadRecords(
                &records, storage: storage, exclusionRules: exclusionRules,
                result: &result, insertedIDs: &insertedIDs
            )
        } catch {
            try? commit()
            throw error
        }
        try commit()
        result.itemsImported = insertedIDs.count
        return result
    }

    /// The path a record without a payload takes: the type is read again from the text and never trusted from the
    /// file, a secret is masked, every preview but a real colour is sealed, and a record whose preview cannot be sealed
    /// is skipped rather than stored in the clear.
    private func insertNew(
        _ records: [HistoryRecord], collectionID: UUID?, result: inout CollectionImportResult
    ) throws
    -> [UUID] {
        var inserted: [UUID] = []
        try insertText(records, collectionID: collectionID, mintsIDs: false, result: &result, insertedIDs: &inserted)
        return inserted
    }

    /// `mintsIDs` is for a collection file: the clips get new ids and are matched to the history by content. A history
    /// file keeps its ids and is matched by id.
    private func insertText(
        _ records: [HistoryRecord], collectionID: UUID?, mintsIDs: Bool, result: inout CollectionImportResult,
        insertedIDs: inout [UUID]
    ) throws {
        // A key that cannot be had fails the import: clips are never stored under a plain hash.
        let key = try BlobEncryption().loadOrCreateKey()
        let existingIDs = mintsIDs ? [] : try Set(modelContext.fetch(FetchDescriptor<ClipboardItem>()).map(\.id))
        let tombstonedIDs = mintsIDs ? [] :
            try Set(modelContext.fetch(FetchDescriptor<DeletedItemTombstone>()).map(\.id))
        var seenHashes = Set<String>()
        for record in records {
            guard Self.isTextual(record.type) else {
                result.skippedUnreadable += 1
                continue
            }
            guard record.previewText.count <= Self.maxRecordCharacters else {
                result.skippedTooLarge += 1
                continue
            }
            if mintsIDs {
                let forms = ContentHash.candidates(for: Self.contentHash(of: record.previewText), key: key)
                let sameContent =
                    FetchDescriptor<ClipboardItem>(predicate: #Predicate { forms.contains($0.contentHash) })
                if try modelContext.fetchCount(sameContent) > 0 || !seenHashes.insert(forms[0]).inserted {
                    result.alreadyPresent += 1
                    continue
                }
            } else if existingIDs.contains(record.id) || tombstonedIDs.contains(record.id) {
                result.alreadyPresent += 1
                continue
            }
            let id = mintsIDs ? UUID() : record.id
            guard let item = makeItem(from: record, id: id, key: key, atFirstCopy: mintsIDs) else {
                result.skippedUnreadable += 1
                continue
            }
            item.collectionID = collectionID
            modelContext.insert(item)
            if let blob = textBlob(for: item) {
                item.blob = blob
                modelContext.insert(blob)
            }
            insertedIDs.append(id)
        }
    }

    /// `atFirstCopy` is a collection file's clip: it enters the history now, and the file's date is only when it was
    /// first copied (ADR 0021). Otherwise a date after now is brought back to now.
    private func makeItem(
        from record: HistoryRecord,
        id: UUID,
        key: SymmetricKey?,
        atFirstCopy: Bool
    )
    -> ClipboardItem? {
        let preview = record.previewText
        let clipType = ContentClassifier.classify(text: preview).type
        let sensitivity = SensitiveContentDetector.detect(in: preview)
        var storedPreview = sensitivity?.maskedPreview ?? preview
        var envelope: BlobEncryption.EncryptedEnvelope?
        if sensitivity == nil, ColorPreviewPolicy.sealsPreview(of: clipType, preview: preview) {
            guard let data = preview.data(using: .utf8), let sealed = try? sealPreview(data, id) else {
                return nil
            }
            envelope = sealed
            storedPreview = ""
        }
        let item = ClipboardItem(
            id: id,
            timestamp: atFirstCopy ? .now : min(record.timestamp, .now),
            type: clipType,
            sourceBundleID: record.sourceBundleID,
            sourceAppName: record.sourceApp,
            sourceDominantColorHex: nil,
            previewText: storedPreview,
            sensitivity: sensitivity?.category,
            sensitivityMaskedPreview: sensitivity?.maskedPreview,
            contentHash: ContentHash.stored(Self.contentHash(of: preview), key: key),
            perceptualHash: nil,
            byteSize: preview.utf8.count,
            deviceID: "import",
            sequenceNumber: 0
        )
        item.previewCiphertext = envelope?.ciphertext
        item.previewNonce = envelope?.nonce
        item.previewAADBound = envelope != nil
        item.customTitle = record.customTitle
        item.userNote = record.userNote
        item.tags = record.tags
        item.isPinned = record.isPinned
        if atFirstCopy { item.adoptFirstCopy(record.timestamp) }
        return item
    }
}
