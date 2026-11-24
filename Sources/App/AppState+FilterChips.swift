// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// One search filter chip as the keyboard sees it.
struct FilterChipAction {
    let spokenName: String
    let isActive: () -> Bool
    let toggle: () -> Void
    var confirmation: String?
}

extension AppState {
    /// Tab (`delta` 1) and Shift-Tab (-1) in search. Returns false when there are no chips, so the key goes on.
    @discardableResult
    func moveFilterChipCursor(by delta: Int) -> Bool {
        guard !filterChipActions.isEmpty else { return false }
        filterChipCursor = FilterChipCursor.moved(from: filterChipCursor, by: delta, count: filterChipActions.count)
        if let cursor = filterChipCursor {
            let chip = filterChipActions[cursor]
            let stateLabel = chip.isActive() ? String(localized: "on") : String(localized: "off")
            Announcer.announce(chip.confirmation == nil ? "\(chip.spokenName), \(stateLabel)" : chip.spokenName)
        } else {
            Announcer.announce(String(localized: "Search field"))
        }
        return true
    }

    /// Return or Space on the chip the cursor is on. False when the cursor is on the field.
    @discardableResult
    func toggleFilterChipAtCursor() -> Bool {
        guard let cursor = FilterChipCursor.kept(filterChipCursor, count: filterChipActions.count) else { return false }
        let chip = filterChipActions[cursor]
        chip.toggle()
        let stateLabel = chip.isActive() ? String(localized: "on") : String(localized: "off")
        Announcer.announce(chip.confirmation ?? "\(chip.spokenName), \(stateLabel)")
        return true
    }

    /// Esc on a chip goes back to the field; false when the cursor is already there.
    @discardableResult
    func releaseFilterChipCursor() -> Bool {
        guard filterChipCursor != nil else { return false }
        filterChipCursor = nil
        return true
    }
}

extension AppState {
    /// The No results button is the last stop Tab reaches in search, after the chips (`registerFilterChipActions`).
    var isKeyboardOnNoResultsAdvice: Bool {
        noResultsAdvice != nil && filterChipCursor == filterChipActions.count - 1
    }

    func clearForNoResults(_ action: NoResultsAdvice.Action) {
        cancelAsk()
        switch action {
        case .clearFilters: clearSearchFilters()
        case .clearSearch: searchText = ""
        }
    }

    /// A link or script chose what the shelf shows (a collection, a search): a long absence must not undo it.
    func noteContextRequested() {
        shelfClosedAt = nil
        shelfContextWasStale = false
    }

    /// Called as the shelf opens. After `ShelfContextPolicy.memory` closed the shelf forgets its collection and
    /// filters; `restingCollectionID` is the frontmost app's own collection, if it has one.
    func resetShelfContextIfStale(now: Date = .now, restingCollectionID: UUID?) {
        let stale = !isPinnedWindowVisible && ShelfContextPolicy.shouldReset(closedAt: shelfClosedAt, now: now)
        shelfContextWasStale = stale
        guard stale else { return }
        cancelAsk()
        searchText = ""
        isSearchActive = false
        showsCustomDateRange = false
        filterChipCursor = nil
        clearSearchFilters()
        appChipFilter = []
        selectedCollectionID = restingCollectionID
    }

    /// A key typed on the shelf with no search open opens the search with that key. Keys that arrive before the field
    /// has focus (it takes a moment) join what was typed, in order.
    func typeIntoSearch(_ characters: String) {
        cancelAsk()
        searchText = isSearchActive ? searchText + characters : characters
        isSearchActive = true
    }

    func clearSearchFilters() {
        searchTypeFilter = []
        searchDateFilter = .all
        showsCustomDateRange = false
        searchSourceFilter = []
        showHiddenNSFW = false
        searchSensitiveOnly = false
        searchRemoteOnly = false
    }

    func noResultsChipAction() -> FilterChipAction? {
        guard let advice = noResultsAdvice else { return nil }
        return FilterChipAction(
            spokenName: advice.buttonTitle,
            isActive: { false },
            toggle: { [weak self] in self?.clearForNoResults(advice.action) },
            confirmation: advice.action == .clearFilters
                ? String(localized: "Filters cleared")
                : String(localized: "Search cleared")
        )
    }
}
