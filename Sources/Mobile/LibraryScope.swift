// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

enum LibraryScope: Hashable {
    case all
    case pinned
    case kind(ClipboardType)
    case collection(UUID)

    static let filteredKinds: [ClipboardType] = [.text, .url, .image, .color, .code, .file]

    var title: String {
        switch self {
        case .all: String(localized: "All Clips")
        case .pinned: String(localized: "Pinned")
        case let .kind(type): Self.kindTitle(type)
        case .collection: String(localized: "Collection")
        }
    }

    var symbolName: String {
        switch self {
        case .all: "tray.full"
        case .pinned: "pin"
        case let .kind(type): type.presentation.symbolName
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

    /// The clips this scope shows for `query`, newest first (a plain collection keeps its own order). A smart
    /// collection's rule reads the clip, so it arrives as `smartRule`; everything else is decided on the index.
    func ids(
        in index: HistoryIndex, query: String, smartRule: ((UUID) -> Bool)? = nil, hidesSensitive: Bool = false,
        now: Date = .now
    )
    -> [UUID] {
        var criteria = HistoryCriteria(
            hidesSensitive: hidesSensitive, query: query.trimmingCharacters(in: .whitespaces), now: now
        )
        switch self {
        case .all:
            break
        case .pinned:
            criteria.pinnedOnly = true
        case let .kind(type):
            criteria.searchActive = true
            criteria.types = [type.rawValue]
        case let .collection(id):
            if smartRule == nil { criteria.collectionID = id }
        }
        return index.matching(criteria, smartCollection: smartRule)
    }
}
