// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// What the shelf asks of the history: the scope (hidden clips, app chips, collection), the typed text, and the
/// search-bar chips, which apply only while a search is open.
public struct HistoryCriteria: Sendable {
    public var hidesSensitive: Bool
    public var appBundleIDs: Set<String>
    public var collectionID: UUID?
    public var searchActive: Bool
    public var types: Set<String>
    public var sources: Set<String>
    public var dateCutoff: Date?
    public var dateBefore: Date?
    public var sensitiveOnly: Bool
    public var remoteOnly: Bool
    public var query: String

    public init(
        hidesSensitive: Bool = false,
        appBundleIDs: Set<String> = [],
        collectionID: UUID? = nil,
        searchActive: Bool = false,
        types: Set<String> = [],
        sources: Set<String> = [],
        dateCutoff: Date? = nil,
        dateBefore: Date? = nil,
        sensitiveOnly: Bool = false,
        remoteOnly: Bool = false,
        query: String = ""
    ) {
        self.hidesSensitive = hidesSensitive
        self.appBundleIDs = appBundleIDs
        self.collectionID = collectionID
        self.searchActive = searchActive
        self.types = types
        self.sources = sources
        self.dateCutoff = dateCutoff
        self.dateBefore = dateBefore
        self.sensitiveOnly = sensitiveOnly
        self.remoteOnly = remoteOnly
        self.query = query
    }
}

/// One clip reduced to plain values, so filtering the history for a keystroke reads no SwiftData property at all: a
/// `@Model` getter costs about 0.65 µs, and the shelf used to make some twenty per clip per keystroke.
public struct HistoryRow: Sendable {
    public let id: UUID
    public let modelID: PersistentIdentifier
    let timestamp: Date
    let typeRaw: String
    let sourceBundleID: String?
    let isNSFW: Bool
    let isSecret: Bool
    let isRemote: Bool
    let collectionID: UUID?
    let tagsLowercased: [String]
    let languageLowercased: String?
    /// The preview, title, note and tags, each folded for case and accents and separated by `separator`.
    var haystack: [UInt8]

    static let separator: UInt8 = 0x01

    public init(_ item: ClipboardItem, includingText: Bool = true) {
        id = item.id
        modelID = item.persistentModelID
        timestamp = item.timestamp
        typeRaw = item.typeRaw
        sourceBundleID = item.sourceBundleID
        isNSFW = item.isNSFW
        isSecret = item.sensitivityRaw != nil
        isRemote = item.isRemote
        collectionID = item.collectionID
        let metadata = item.metadata
        let tags = metadata.tags
        tagsLowercased = tags.map { $0.lowercased() }
        languageLowercased = item.detectedLanguage?.lowercased()
        guard includingText else {
            haystack = []
            return
        }
        var parts = [item.searchableGridPreview]
        parts.append(metadata.customTitle.map(SearchMatching.fold) ?? "")
        parts.append(metadata.userNote.map(SearchMatching.fold) ?? "")
        parts.append(contentsOf: tags.map(SearchMatching.fold))
        var bytes: [UInt8] = []
        for (position, part) in parts.enumerated() {
            if position > 0 { bytes.append(Self.separator) }
            bytes.append(contentsOf: part.utf8)
        }
        haystack = bytes
    }

    func contains(_ needle: [UInt8]) -> Bool {
        guard !haystack.isEmpty, !needle.isEmpty, needle.count <= haystack.count else { return false }
        return haystack.withUnsafeBytes { hay in
            needle.withUnsafeBytes { memmem(hay.baseAddress, hay.count, $0.baseAddress, $0.count) != nil }
        }
    }
}

/// The history as rows, newest first, kept up to date from what each save changed. It holds the decrypted, folded text
/// of every clip, so it is dropped with `PreviewTextCache` whenever the history locks or is cleared.
public struct HistoryIndex: Sendable {
    public private(set) var rows: [HistoryRow]
    public private(set) var hasSearchText: Bool

    public init(items: [ClipboardItem]) {
        rows = items.map { HistoryRow($0) }
        rows.sort { $0.timestamp > $1.timestamp }
        hasSearchText = true
    }

    public init(rows: [HistoryRow]) {
        self.rows = rows.sorted { $0.timestamp > $1.timestamp }
        hasSearchText = true
    }

    public var count: Int {
        rows.count
    }

    /// Inserts a clip, or replaces the row it already has, at the place its timestamp gives it.
    public mutating func apply(upserting items: [ClipboardItem]) {
        for item in items {
            let row = HistoryRow(item, includingText: hasSearchText)
            if let existing = rows.firstIndex(where: { $0.modelID == row.modelID }) { rows.remove(at: existing) }
            rows.insert(row, at: insertionIndex(for: row.timestamp))
        }
    }

    public mutating func apply(removing identifiers: Set<PersistentIdentifier>) {
        guard !identifiers.isEmpty else { return }
        rows.removeAll { identifiers.contains($0.modelID) }
    }

    /// Forgets the plaintext (the history locked): the rows stay, so the shelf keeps its order, but nothing matches a
    /// typed query until the text is rebuilt.
    public mutating func dropSearchText() {
        for position in rows.indices {
            rows[position].haystack = []
        }
        hasSearchText = false
    }

    public func ids() -> [UUID] {
        rows.map(\.id)
    }

    /// The ids of the clips that pass `criteria`, in the history's order. A smart collection is the caller's rule,
    /// because it reads the clip itself; it replaces the plain collection check.
    public func matching(_ criteria: HistoryCriteria, smartCollection: ((UUID) -> Bool)? = nil) -> [UUID] {
        let text = TextQuery(criteria.query)
        if text.cannotMatch { return [] }
        return rows.filter { row in
            Self.inScope(row, criteria, smartCollection) && text.matches(row)
                && (!criteria.searchActive || Self.passesChips(row, criteria))
        }.map(\.id)
    }

    /// Hidden clips, the app chips and the collection.
    private static func inScope(
        _ row: HistoryRow, _ criteria: HistoryCriteria, _ smartCollection: ((UUID) -> Bool)?
    )
    -> Bool {
        if criteria.hidesSensitive, row.isNSFW { return false }
        let apps = criteria.searchActive ? criteria.appBundleIDs.union(criteria.sources) : criteria.appBundleIDs
        if !apps.isEmpty, !(row.sourceBundleID.map(apps.contains) ?? false) {
            return false
        }
        if let smartCollection { return smartCollection(row.id) }
        guard let collection = criteria.collectionID else { return true }
        return row.collectionID == collection
    }

    /// The search bar's chips, which apply only while a search is open.
    private static func passesChips(_ row: HistoryRow, _ criteria: HistoryCriteria) -> Bool {
        if !criteria.types.isEmpty, !criteria.types.contains(row.typeRaw) { return false }
        if let cutoff = criteria.dateCutoff, row.timestamp < cutoff { return false }
        if let before = criteria.dateBefore, row.timestamp >= before { return false }
        if criteria.sensitiveOnly, !row.isNSFW, !row.isSecret { return false }
        if criteria.remoteOnly, !row.isRemote { return false }
        return true
    }

    /// What was typed: `@prefix` asks for a tag by prefix or a language exactly, anything else is folded text.
    private struct TextQuery {
        let isEmpty: Bool
        let tagPrefix: String?
        let needle: [UInt8]
        let cannotMatch: Bool

        init(_ raw: String) {
            let query = raw.trimmingCharacters(in: .whitespaces)
            isEmpty = query.isEmpty
            tagPrefix = query.hasPrefix("@") ? query.dropFirst().lowercased() : nil
            needle = tagPrefix == nil ? Array(SearchMatching.fold(query).utf8) : []
            cannotMatch = needle.contains(HistoryRow.separator)
        }

        func matches(_ row: HistoryRow) -> Bool {
            if isEmpty { return true }
            guard let tagPrefix else { return row.contains(needle) }
            return row.tagsLowercased.contains { $0.hasPrefix(tagPrefix) } || row.languageLowercased == tagPrefix
        }
    }

    private func insertionIndex(for timestamp: Date) -> Int {
        var low = 0
        var high = rows.count
        while low < high {
            let middle = (low + high) / 2
            if rows[middle].timestamp > timestamp { low = middle + 1 } else { high = middle }
        }
        return low
    }
}

/// The clips a save inserted, updated and deleted, read from `ModelContext.didSave`. Saves also carry blobs and
/// collections; those are not history rows and are left out.
public struct HistorySaveChange: Sendable, Equatable {
    public let inserted: [PersistentIdentifier]
    public let updated: [PersistentIdentifier]
    public let deleted: [PersistentIdentifier]

    private static let clipEntity = String(describing: ClipboardItem.self)

    public init?(userInfo: [AnyHashable: Any]?) {
        guard let userInfo,
              userInfo[ModelContext.NotificationKey.insertedIdentifiers.rawValue] != nil
              || userInfo[ModelContext.NotificationKey.updatedIdentifiers.rawValue] != nil
              || userInfo[ModelContext.NotificationKey.deletedIdentifiers.rawValue] != nil else { return nil }
        func clips(_ key: ModelContext.NotificationKey) -> [PersistentIdentifier] {
            (userInfo[key.rawValue] as? [PersistentIdentifier] ?? []).filter { $0.entityName == Self.clipEntity }
        }
        inserted = clips(.insertedIdentifiers)
        updated = clips(.updatedIdentifiers)
        deleted = clips(.deletedIdentifiers)
    }

    public var touchesNoClip: Bool {
        inserted.isEmpty && updated.isEmpty && deleted.isEmpty
    }

    public var count: Int {
        inserted.count + updated.count + deleted.count
    }
}
