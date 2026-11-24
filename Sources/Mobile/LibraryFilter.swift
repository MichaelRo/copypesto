// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import SwiftUI

enum LibraryChip: Hashable {
    case all
    case pinned
    case collection(UUID)
    case newCollection
    case scopeDivider
    case filterDivider
    case kind(ClipboardType)
    case when
    case from
    case sensitive
    case otherDevices
    /// Ask Pesto: turns the typed sentence into filters (`MobileAppState+Ask.swift`).
    case ask
    /// What Ask Pesto filtered by; choosing it takes the filters off and keeps the words.
    case asked

    /// `offersAsk` is true while the search field holds words and no Ask is applied; `hasAsk` while one is.
    static func row(
        collectionIDs: [UUID],
        isSearching: Bool,
        offersAsk: Bool = false,
        hasAsk: Bool = false,
        hiddenIDs: Set<UUID> = [],
        showsScopes: Bool = true,
        showsFrom: Bool = false
    )
    -> [LibraryChip] {
        let visibleCollections = collectionIDs.filter { !hiddenIDs.contains($0) }
        let scopes: [LibraryChip] = showsScopes
            ? [.all, .pinned] + visibleCollections.map(LibraryChip.collection)
            : []
        guard isSearching else { return scopes + [.newCollection] }
        let asking: [LibraryChip] = hasAsk ? [.asked] : offersAsk ? [.ask] : []
        var filters: [LibraryChip] = [.when]
        if showsFrom { filters.append(.from) }
        filters.append(contentsOf: [.sensitive, .otherDevices])
        let leading = scopes.isEmpty ? asking : scopes + [.scopeDivider] + asking
        return leading + LibraryScope.filteredKinds.map(LibraryChip.kind) + [.filterDivider] + filters
    }

    var scope: LibraryScope? {
        switch self {
        case .all: .all
        case .pinned: .pinned
        case let .collection(id): .collection(id)
        case .newCollection, .scopeDivider, .filterDivider, .kind, .when, .from, .sensitive, .otherDevices, .ask,
             .asked:
            nil
        }
    }
}

struct LibraryFilter: Equatable {
    var scope: LibraryScope = .all
    var kind: ClipboardType?
    var dateFilter: SearchDateFilter = .all
    var sourceBundleID: String?
    var sensitiveOnly = false
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

    /// The date filter in force: the explicit When menu choice, else Ask Pesto's range.
    var effectiveDateFilter: SearchDateFilter {
        dateFilter != .all ? dateFilter : askedRange
    }

    var hasAnySearchFilter: Bool {
        kind != nil || dateFilter != .all || sourceBundleID != nil || sensitiveOnly || otherDevicesOnly || hasAsk
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
        case .when: dateFilter != .all
        case .from: sourceBundleID != nil
        case .sensitive: sensitiveOnly
        case .otherDevices: otherDevicesOnly
        default: chip.scope == scope
        }
    }

    mutating func choose(_ chip: LibraryChip) {
        switch chip {
        case let .kind(type):
            kind = kind == type ? nil : type
            askedKinds = []
        case .sensitive:
            sensitiveOnly.toggle()
        case .otherDevices:
            otherDevicesOnly.toggle()
        case .asked:
            clearAsk()
        case .when, .from, .ask:
            break
        default:
            if let chosen = chip.scope { scope = chosen }
        }
    }

    mutating func chooseDate(_ chosen: SearchDateFilter) {
        dateFilter = chosen
        askedRange = .all
    }

    mutating func chooseSource(_ bundleID: String?) {
        guard let bundleID else {
            sourceBundleID = nil
            return
        }
        sourceBundleID = sourceBundleID == bundleID ? nil : bundleID
    }

    mutating func clearSearchFilters() {
        kind = nil
        dateFilter = .all
        sourceBundleID = nil
        sensitiveOnly = false
        otherDevicesOnly = false
        clearAsk()
    }

    mutating func endSearch() {
        clearSearchFilters()
    }

    /// Ask Pesto's answer replaces the kind and date chips with what it found.
    mutating func apply(_ query: AskPestoQuery) {
        kind = nil
        dateFilter = .all
        askedKinds = Set(query.types)
        askedRange = query.range
    }

    mutating func clearAsk() {
        askedKinds = []
        askedRange = .all
    }

    /// The date range a search is narrowed to: the chosen filter, else the one Ask found, with the Mac's rules for it.
    func dateWindow(now: Date = .now) -> (cutoff: Date?, before: Date?) {
        let shelf = ShelfFilter(
            hidesSensitive: false, searchActive: true, types: [], sources: [], date: effectiveDateFilter,
            sensitiveOnly: false, now: now
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

    @MainActor
    static func availableApps(in items: [ClipboardItem]) -> [SourceApp] {
        guard !items.isEmpty else { return [] }
        var tally = SuggestionTally()
        for item in items {
            tally.add(tags: [], bundleID: item.sourceBundleID, appName: item.knownSourceAppName)
        }
        return tally.suggestions(tagLimit: 0, appLimit: 0).allApps
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

    static func showsChipRow(
        isRegular: Bool, columns: NavigationSplitViewVisibility, isSearching: Bool = false
    )
    -> Bool {
        !isRegular || columns == .detailOnly || isSearching
    }
}
