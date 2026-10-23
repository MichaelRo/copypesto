// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData

/// JSON export/import for clipboard history.
/// Export format: array of HistoryRecord objects — no blobs, no encrypted data.
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
    }

    /// The kinds a text export carries. A picture's preview is the text read out of it and a file's is its full path,
    /// neither of which the person expects in a file of "text previews"; an imported one would be a card with no
    /// payload.
    private static let textualTypes: Set<ClipboardType> = [.text, .code, .url, .color]

    private static func isTextual(_ rawType: String) -> Bool {
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
    private static func contentHash(of text: String) -> String {
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
    }

    private var sealPreview: @Sendable (Data, UUID) throws -> BlobEncryption.EncryptedEnvelope = { data, id in
        try BlobEncryption().encrypt(data, associatedData: BlobEncryption.associatedData(itemID: id, field: .preview))
    }

    func useSealer(_ sealer: @escaping @Sendable (Data, UUID) throws -> BlobEncryption.EncryptedEnvelope) {
        sealPreview = sealer
    }

    /// Reads an import file, refusing one over `maxImportBytes` before any of it is loaded.
    private static func boundedContents(of url: URL) throws -> Data {
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        guard size <= maxImportBytes else { throw ImportError.fileTooLarge }
        return try Data(contentsOf: url)
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
        let inserted = try insertNew(records, collectionID: nil).count
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

        public init(version: Int = 1, collection: CollectionMetadata, items: [HistoryRecord]) {
            self.version = version
            self.collection = collection
            self.items = items
        }
    }

    public func exportCollection(id: UUID) throws -> Data {
        let boards = try modelContext.fetch(FetchDescriptor<Pinboard>())
        guard let board = boards.first(where: { $0.id == id }) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let allItems = try modelContext.fetch(
            FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        )
        let items = allItems.filter { $0.collectionID == id && Self.isTextual($0.typeRaw) }
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
        let payload = CollectionExportPayload(
            version: 1,
            collection: .init(
                id: board.id,
                name: board.name,
                symbolName: board.symbolName,
                colorHex: board.colorHex,
                isSmart: board.isSmart,
                smartPredicateData: board.smartPredicateData
            ),
            items: records
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    /// The collection as a file at `url`, written whole or not at all, so a failed export never leaves half a file.
    public func writeCollection(id: UUID, to url: URL) throws {
        try PrivateFile.write(exportCollection(id: id), to: url)
    }

    @discardableResult
    public func importCollection(
        fromFile url: URL, undoHistory: UndoHistory? = nil
    ) throws
    -> (collectionID: UUID, itemsImported: Int) {
        try importCollection(from: Self.boundedContents(of: url), undoHistory: undoHistory)
    }

    /// Adds a collection file's clips (and its collection, when none by that id or name exists). With an
    /// `undoHistory` the import is remembered as one action that Undo takes back.
    @discardableResult
    public func importCollection(
        from data: Data, undoHistory: UndoHistory? = nil
    ) throws
    -> (collectionID: UUID, itemsImported: Int) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(CollectionExportPayload.self, from: data)
        guard payload.items.count <= Self.maxRecords else { throw ImportError.tooManyRecords }

        let existingBoards = try modelContext.fetch(FetchDescriptor<Pinboard>())
        let targetBoard: Pinboard
        var createdBoard: PinboardSnapshot?
        if let existing = existingBoards.first(where: {
            $0.id == payload.collection.id || $0.name == payload.collection.name
        }) {
            targetBoard = existing
        } else {
            let maxSort = (existingBoards.map(\.sortOrder).max() ?? 0) + 1
            let newBoard = Pinboard(
                id: payload.collection.id,
                name: payload.collection.name,
                symbolName: payload.collection.symbolName,
                colorHex: payload.collection.colorHex,
                sortOrder: maxSort,
                isSmart: payload.collection.isSmart,
                smartPredicateData: payload.collection.smartPredicateData
            )
            modelContext.insert(newBoard)
            targetBoard = newBoard
            createdBoard = PinboardSnapshot(newBoard)
        }

        let insertedIDs = try insertNew(payload.items, collectionID: targetBoard.id)
        let changedSomething = !insertedIDs.isEmpty || createdBoard != nil
        if changedSomething { try modelContext.saveOrRollback() }
        if let undoHistory, changedSomething, insertedIDs.count <= UndoPolicy.maxClipsPerEntry {
            let added = AddedClips(kind: .collection, ids: insertedIDs, boards: createdBoard.map { [$0] } ?? [])
            undoHistory.record(UndoEntry(.clipsAdded(added)))
        }
        return (targetBoard.id, insertedIDs.count)
    }

    /// The one path every imported record takes: the type is read again from the text and never trusted from the
    /// file, a secret is masked, every preview but a real colour is sealed, and a record whose preview cannot be sealed
    /// is skipped rather than stored in the clear.
    private func insertNew(_ records: [HistoryRecord], collectionID: UUID?) throws -> [UUID] {
        let existingIDs = try Set(modelContext.fetch(FetchDescriptor<ClipboardItem>()).map(\.id))
        let tombstonedIDs = try Set(modelContext.fetch(FetchDescriptor<DeletedItemTombstone>()).map(\.id))
        let key = try? BlobEncryption().loadOrCreateKey()
        var inserted: [UUID] = []
        for record in records
            where Self.isTextual(record.type) && !existingIDs.contains(record.id) && !tombstonedIDs.contains(record.id)
            && record.previewText.count <= Self.maxRecordCharacters
        {
            guard let item = makeItem(from: record, key: key) else { continue }
            item.collectionID = collectionID
            modelContext.insert(item)
            if let blob = textBlob(for: item) {
                item.blob = blob
                modelContext.insert(blob)
            }
            inserted.append(record.id)
        }
        return inserted
    }

    private func makeItem(from record: HistoryRecord, key: SymmetricKey?) -> ClipboardItem? {
        let preview = record.previewText
        let clipType = ContentClassifier.classify(text: preview).type
        let sensitivity = SensitiveContentDetector.detect(in: preview)
        var storedPreview = sensitivity?.maskedPreview ?? preview
        var envelope: BlobEncryption.EncryptedEnvelope?
        if sensitivity == nil, ColorPreviewPolicy.sealsPreview(of: clipType, preview: preview) {
            guard let data = preview.data(using: .utf8), let sealed = try? sealPreview(data, record.id) else {
                return nil
            }
            envelope = sealed
            storedPreview = ""
        }
        let item = ClipboardItem(
            id: record.id,
            timestamp: record.timestamp,
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
        return item
    }
}
