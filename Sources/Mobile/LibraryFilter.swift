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
    /// Ask Pesto: turns the typed sentence into filters (`MobileAppState+Ask.swift`).
    case ask
    /// What Ask Pesto filtered by; choosing it takes the filters off and keeps the words.
    case asked

    /// `offersAsk` is true while the search field holds words and no Ask is applied; `hasAsk` while one is.
    static func row(
        collectionIDs: [UUID], isSearching: Bool, offersAsk: Bool = false, hasAsk: Bool = false,
        hiddenIDs: Set<UUID> = []
    )
    -> [LibraryChip] {
        let visibleCollections = collectionIDs.filter { !hiddenIDs.contains($0) }
        let scopes: [LibraryChip] = [.all, .pinned] + visibleCollections.map(LibraryChip.collection)
        guard isSearching else { return scopes + [.newCollection] }
        let asking: [LibraryChip] = hasAsk ? [.asked] : offersAsk ? [.ask] : []
        return scopes + [.divider] + asking + LibraryScope.filteredKinds.map(LibraryChip.kind) + [.divider]
            + LibraryDateChip.allCases.map(LibraryChip.date) + [.otherDevices]
    }

    var scope: LibraryScope? {
        switch self {
        case .all: .all
        case .pinned: .pinned
        case let .collection(id): .collection(id)
        case .newCollection, .divider, .kind, .date, .otherDevices, .ask, .asked: nil
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
    /// What Ask Pesto found in a sentence (`apply`): kinds and a date range beside the words, which go to the search
    /// field. A kind or date chip chosen afterwards takes over from its half.
    var askedKinds: Set<ClipboardType> = []
    var askedRange: SearchDateFilter = .all

    var hasAsk: Bool {
        !askedKinds.isEmpty || askedRange != .all
    }

    /// The kinds a search is narrowed to: the chosen chip, else the ones Ask found.
    var kinds: Set<ClipboardType> {
        kind.map { [$0] } ?? askedKinds
    }

    /// What the Ask chip says: its kinds and range, never the words (they are in the field).
    var askedSummary: String {
        AskPestoQuery(
            keywords: "", types: LibraryScope.filteredKinds.filter(askedKinds.contains), range: askedRange
        ).summary
    }

    func isSelected(_ chip: LibraryChip) -> Bool {
        switch chip {
        case .asked: hasAsk
        case .ask: false
        case let .kind(type): kind == type
        case let .date(chosen): date == chosen
        case .otherDevices: otherDevicesOnly
        default: chip.scope == scope
        }
    }

    mutating func choose(_ chip: LibraryChip) {
        switch chip {
        case let .kind(type):
            kind = kind == type ? nil : type
            askedKinds = []
        case let .date(chosen):
            date = date == chosen ? nil : chosen
            askedRange = .all
        case .otherDevices: otherDevicesOnly.toggle()
        case .asked: clearAsk()
        case .ask: break
        default:
            if let chosen = chip.scope { scope = chosen }
        }
    }

    mutating func endSearch() {
        kind = nil
        date = nil
        otherDevicesOnly = false
        clearAsk()
    }

    /// Ask Pesto's answer replaces the kind and date chips with what it found.
    mutating func apply(_ query: AskPestoQuery) {
        kind = nil
        date = nil
        askedKinds = Set(query.types)
        askedRange = query.range
    }

    mutating func clearAsk() {
        askedKinds = []
        askedRange = .all
    }

    /// The date range a search is narrowed to: the chosen chip, else the one Ask found, with the Mac's rules for it.
    func dateWindow(now: Date = .now) -> (cutoff: Date?, before: Date?) {
        let range = date?.searchDate ?? askedRange
        let shelf = ShelfFilter(
            hidesSensitive: false, searchActive: true, types: [], sources: [], date: range, sensitiveOnly: false,
            now: now
        )
        return (shelf.dateCutoff, shelf.dateBefore)
    }

    /// The oldest timestamp the date lets through.
    func dateCutoff(now: Date = .now) -> Date? {
        dateWindow(now: now).cutoff
    }

    mutating func forget(collections existing: [UUID]) {
        if case let .collection(id) = scope, !existing.contains(id) { scope = .all }
    }
}

enum LibraryChrome {
    /// A regular width narrower than this (an iPad window in Split View or Slide Over) starts with the sidebar hidden
    /// and
    /// the chip row in its place.
    static let sidebarMinimumWidth: CGFloat = 800

    static func initialColumns(width: CGFloat) -> NavigationSplitViewVisibility {
        width < sidebarMinimumWidth ? .detailOnly : .all
    }

    static func showsChipRow(isRegular: Bool, columns: NavigationSplitViewVisibility) -> Bool {
        !isRegular || columns == .detailOnly
    }
}
