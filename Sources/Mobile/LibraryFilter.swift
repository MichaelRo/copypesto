// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import SwiftUI

enum LibraryChip: Hashable {
    case all
    case pinned
    case collection(UUID)
    case newCollection
    case divider
    case kind(ClipboardType)

    static func row(collectionIDs: [UUID], isSearching: Bool) -> [LibraryChip] {
        let scopes: [LibraryChip] = [.all, .pinned] + collectionIDs.map(LibraryChip.collection)
        guard isSearching else { return scopes + [.newCollection] }
        return scopes + [.divider] + LibraryScope.filteredKinds.map(LibraryChip.kind)
    }

    var scope: LibraryScope? {
        switch self {
        case .all: .all
        case .pinned: .pinned
        case let .collection(id): .collection(id)
        case .newCollection, .divider, .kind: nil
        }
    }
}

struct LibraryFilter: Equatable {
    var scope: LibraryScope = .all
    var kind: ClipboardType?

    func isSelected(_ chip: LibraryChip) -> Bool {
        if case let .kind(type) = chip { return kind == type }
        return chip.scope == scope
    }

    mutating func choose(_ chip: LibraryChip) {
        if case let .kind(type) = chip {
            kind = kind == type ? nil : type
        } else if let chosen = chip.scope {
            scope = chosen
        }
    }

    mutating func endSearch() {
        kind = nil
    }

    mutating func forget(collections existing: [UUID]) {
        if case let .collection(id) = scope, !existing.contains(id) { scope = .all }
    }
}

enum LibraryChrome {
    static func showsChipRow(isRegular: Bool, columns: NavigationSplitViewVisibility) -> Bool {
        !isRegular || columns == .detailOnly
    }
}
