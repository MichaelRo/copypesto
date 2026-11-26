// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

enum LibraryScope: Hashable {
    case all
    case pinned
    case collection(UUID)

    static let filteredKinds: [ClipboardType] = [.text, .url, .image, .color, .code, .file]

    var title: String {
        switch self {
        case .all: String(localized: "All Clips")
        case .pinned: String(localized: "Pinned")
        case .collection: String(localized: "Collection")
        }
    }

    var symbolName: String {
        switch self {
        case .all: "tray.full"
        case .pinned: "pin"
        case .collection: "folder"
        }
    }

    static func kindTitle(_ type: ClipboardType) -> String {
        switch type {
        case .text: String(localized: "Text")
        case .url: String(localized: "Links")
        case .image: String(localized: "Pictures")
        case .color: String(localized: "Colors")
        case .code: String(localized: "Code")
        case .file: String(localized: "Files")
        }
    }

    /// The clips this scope shows for `query`, newest first (a plain collection keeps its own order), narrowed to one
    /// kind while a search offers kinds. A smart collection's rule reads the clip, so it arrives as `smartRule`;
    /// everything else is decided on the index.
    func ids(
        in index: HistoryIndex, query: String, kind: ClipboardType? = nil, kinds: Set<ClipboardType> = [],
        smartRule: ((UUID) -> Bool)? = nil, hidesSensitive: Bool = false, dateCutoff: Date? = nil,
        dateBefore: Date? = nil, sourceBundleID: String? = nil, sensitiveOnly: Bool = false,
        otherDevicesOnly: Bool = false, now: Date = .now, collectionLock: CollectionLock = .none
    )
    -> [UUID] {
        var criteria = HistoryCriteria(
            hidesSensitive: hidesSensitive, query: query.trimmingCharacters(in: .whitespaces), now: now,
            collectionLock: collectionLock
        )
        let narrowed = kind.map { Set([$0]) } ?? kinds
        if !narrowed.isEmpty {
            criteria.searchActive = true
            criteria.types = Set(narrowed.map(\.rawValue))
        }
        if dateCutoff != nil || dateBefore != nil || sourceBundleID != nil || sensitiveOnly || otherDevicesOnly {
            criteria.searchActive = true
            criteria.dateCutoff = dateCutoff
            criteria.dateBefore = dateBefore
            if let sourceBundleID { criteria.sources = [sourceBundleID] }
            criteria.sensitiveOnly = sensitiveOnly
            criteria.remoteOnly = otherDevicesOnly
        }
        switch self {
        case .all:
            break
        case .pinned:
            criteria.pinnedOnly = true
        case let .collection(id):
            if smartRule == nil { criteria.collectionID = id }
        }
        return index.matching(criteria, smartCollection: smartRule)
    }
}
