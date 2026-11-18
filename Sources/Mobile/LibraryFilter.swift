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
    case date(LibraryDateChip)
    case otherDevices

    static func row(collectionIDs: [UUID], isSearching: Bool) -> [LibraryChip] {
        let scopes: [LibraryChip] = [.all, .pinned] + collectionIDs.map(LibraryChip.collection)
        guard isSearching else { return scopes + [.newCollection] }
        return scopes + [.divider] + LibraryScope.filteredKinds.map(LibraryChip.kind) + [.divider]
            + LibraryDateChip.allCases.map(LibraryChip.date) + [.otherDevices]
    }

    var scope: LibraryScope? {
        switch self {
        case .all: .all
        case .pinned: .pinned
        case let .collection(id): .collection(id)
        case .newCollection, .divider, .kind, .date, .otherDevices: nil
        }
    }
}

/// The date chips of a search, with the Mac's meaning (`ShelfFilter.dateCutoff`): Today from the start of the day,
/// This Week the last seven days.
enum LibraryDateChip: CaseIterable, Hashable {
    case today
    case week

    var searchDate: SearchDateFilter {
        switch self {
        case .today: .today
        case .week: .week
        }
    }
}

struct LibraryFilter: Equatable {
    var scope: LibraryScope = .all
    var kind: ClipboardType?
    var date: LibraryDateChip?
    var otherDevicesOnly = false

    func isSelected(_ chip: LibraryChip) -> Bool {
        switch chip {
        case let .kind(type): kind == type
        case let .date(chosen): date == chosen
        case .otherDevices: otherDevicesOnly
        default: chip.scope == scope
        }
    }

    mutating func choose(_ chip: LibraryChip) {
        switch chip {
        case let .kind(type): kind = kind == type ? nil : type
        case let .date(chosen): date = date == chosen ? nil : chosen
        case .otherDevices: otherDevicesOnly.toggle()
        default:
            if let chosen = chip.scope { scope = chosen }
        }
    }

    mutating func endSearch() {
        kind = nil
        date = nil
        otherDevicesOnly = false
    }

    /// The oldest timestamp the date chip lets through, with the Mac's rule for it.
    func dateCutoff(now: Date = .now) -> Date? {
        guard let date else { return nil }
        return ShelfFilter(
            hidesSensitive: false, searchActive: true, types: [], sources: [], date: date.searchDate,
            sensitiveOnly: false, now: now
        ).dateCutoff
    }

    mutating func forget(collections existing: [UUID]) {
        if case let .collection(id) = scope, !existing.contains(id) { scope = .all }
    }
}

enum LibraryChrome {
    /// A regular width narrower than this (an iPad window in Split View or Slide Over) starts with the sidebar hidden and
    /// the chip row in its place.
    static let sidebarMinimumWidth: CGFloat = 800

    static func initialColumns(width: CGFloat) -> NavigationSplitViewVisibility {
        width < sidebarMinimumWidth ? .detailOnly : .all
    }

    static func showsChipRow(isRegular: Bool, columns: NavigationSplitViewVisibility) -> Bool {
        !isRegular || columns == .detailOnly
    }
}
