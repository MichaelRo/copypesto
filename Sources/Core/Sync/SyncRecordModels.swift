// SPDX-License-Identifier: MIT
import Foundation

/// What a person edited about a clip, as the other Macs read it.
public struct SyncCuration: Codable, Equatable, Sendable {
    public var customTitle: String?
    public var userNote: String?
    public var tags: [String] = []
    public var customSymbolName: String?
    public var collectionID: UUID?
    public var collectionOrder: Int?
    public var isPinned = false
    public var expiresAt: Date?

    public init() {}
}

/// A clip as a record says it: the metadata; the bytes are the record's payload (or a blob file, named by `blobName`).
/// Every change to a clip is a whole item record with a later stamp, so a record never depends on one before it.
public struct SyncItemRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var plainHash: String
    public var mimeType: String
    public var timestamp: Date
    public var sourceBundleID: String?
    public var sourceAppName: String?
    public var isRemote = false
    public var blobName: String?
    public var curation = SyncCuration()

    public init(id: UUID, plainHash: String, mimeType: String, timestamp: Date) {
        self.id = id
        self.plainHash = plainHash
        self.mimeType = mimeType
        self.timestamp = timestamp
    }
}

public struct SyncCollectionRecord: Codable, Equatable, Sendable {
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

/// A deletion, or a withdrawal of a clip that must not be in the log. The record's stamp says when.
public struct SyncTombstoneRecord: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case item
        case collection
    }

    public var id: UUID
    public var kind: Kind
    public var plainHash: String?

    public init(id: UUID, kind: Kind, plainHash: String? = nil) {
        self.id = id
        self.kind = kind
        self.plainHash = plainHash
    }
}

public extension SyncStamp {
    /// A stamp that is earlier than every real one, for a row from before sync was on.
    static let origin = SyncStamp(wallMillis: 0, counter: 0, deviceID: "")
}
