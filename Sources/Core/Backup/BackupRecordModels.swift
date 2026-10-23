// SPDX-License-Identifier: MIT
import Foundation

public struct BackupItemMetadata: Codable, Sendable, Equatable {
    public var id: UUID
    public var timestamp: Date
    public var typeRaw: String
    public var mimeType: String
    /// SHA-256 of the payload. The stored content hash is keyed per Mac, so it cannot be compared across Macs.
    public var plainHash: String
    public var sourceBundleID: String?
    public var sourceAppName: String?
    public var customTitle: String?
    public var userNote: String?
    public var tags: [String]
    public var isPinned: Bool
    public var collectionID: UUID?
    public var pinnedHotkeyIndex: Int?
    public var expiresAt: Date?
    public var isNSFW: Bool
    public var pasteCount: Int
    /// The sensitivity category when the clip was hidden, so a restore keeps a credential clip hidden. Absent in
    /// backups made before it existed.
    public var sensitivityRaw: String?
    /// True when the clip arrived from another device. Absent in backups made before it existed (read as false).
    public var isRemote: Bool?

    public init(
        id: UUID, timestamp: Date, typeRaw: String, mimeType: String, plainHash: String,
        sourceBundleID: String? = nil, sourceAppName: String? = nil, customTitle: String? = nil,
        userNote: String? = nil, tags: [String] = [], isPinned: Bool = false, collectionID: UUID? = nil,
        pinnedHotkeyIndex: Int? = nil, expiresAt: Date? = nil, isNSFW: Bool = false, pasteCount: Int = 0,
        sensitivityRaw: String? = nil, isRemote: Bool? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.typeRaw = typeRaw
        self.mimeType = mimeType
        self.plainHash = plainHash
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.customTitle = customTitle
        self.userNote = userNote
        self.tags = tags
        self.isPinned = isPinned
        self.collectionID = collectionID
        self.pinnedHotkeyIndex = pinnedHotkeyIndex
        self.expiresAt = expiresAt
        self.isNSFW = isNSFW
        self.pasteCount = pasteCount
        self.sensitivityRaw = sensitivityRaw
        self.isRemote = isRemote
    }
}

public struct BackupCollectionMetadata: Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var symbolName: String
    public var colorHex: String
    public var sortOrder: Int
    public var isSmart: Bool
    public var smartPredicateData: Data?
    public var schemaVersion: Int
    public var triggerBundleID: String?

    public init(
        id: UUID, name: String, symbolName: String, colorHex: String, sortOrder: Int, isSmart: Bool,
        smartPredicateData: Data?, schemaVersion: Int, triggerBundleID: String?
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.isSmart = isSmart
        self.smartPredicateData = smartPredicateData
        self.schemaVersion = schemaVersion
        self.triggerBundleID = triggerBundleID
    }
}

public struct BackupTombstoneMetadata: Codable, Sendable, Equatable {
    public var id: UUID
    public var deletedAt: Date

    public init(id: UUID, deletedAt: Date) {
        self.id = id
        self.deletedAt = deletedAt
    }
}

public extension BackupRecord {
    static func item(_ metadata: BackupItemMetadata, payload: Data) throws -> BackupRecord {
        try BackupRecord(kind: .item, metadata: JSONEncoder.backupRecords.encode(metadata), payload: payload)
    }

    static func collection(_ metadata: BackupCollectionMetadata) throws -> BackupRecord {
        try BackupRecord(kind: .collection, metadata: JSONEncoder.backupRecords.encode(metadata))
    }

    static func tombstone(_ metadata: BackupTombstoneMetadata) throws -> BackupRecord {
        try BackupRecord(kind: .tombstone, metadata: JSONEncoder.backupRecords.encode(metadata))
    }

    static func settings(_ json: Data) -> BackupRecord {
        BackupRecord(kind: .settings, metadata: json)
    }

    func itemMetadata() throws -> BackupItemMetadata {
        try decode(.item)
    }

    func collectionMetadata() throws -> BackupCollectionMetadata {
        try decode(.collection)
    }

    func tombstoneMetadata() throws -> BackupTombstoneMetadata {
        try decode(.tombstone)
    }

    private func decode<T: Decodable>(_ expected: Kind) throws -> T {
        guard kind == expected, let value = try? JSONDecoder.backupRecords.decode(T.self, from: metadata) else {
            throw BackupError.corrupted
        }
        return value
    }
}

extension JSONEncoder {
    static var backupRecords: JSONEncoder {
        let encoder = JSONEncoder()
        // Dates stay exact (seconds as a number): ordering ties within one second must survive a restore.
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var backupRecords: JSONDecoder {
        JSONDecoder()
    }
}
