// SPDX-License-Identifier: MIT
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
            Announcer
                .announce(chip.confirmation == nil ? "\(chip.spokenName), \(chip.isActive() ? "on" : "off")" : chip
                    .spokenName)
        } else {
            Announcer.announce("Search field")
        }
        return true
    }

    /// Return or Space on the chip the cursor is on. False when the cursor is on the field.
    @discardableResult
    func toggleFilterChipAtCursor() -> Bool {
        guard let cursor = FilterChipCursor.kept(filterChipCursor, count: filterChipActions.count) else { return false }
        let chip = filterChipActions[cursor]
        chip.toggle()
        Announcer.announce(chip.confirmation ?? "\(chip.spokenName), \(chip.isActive() ? "on" : "off")")
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
        switch action {
        case .clearFilters: clearSearchFilters()
        case .clearSearch: searchText = ""
        }
    }

    func noResultsChipAction() -> FilterChipAction? {
        guard let advice = noResultsAdvice else { return nil }
        return FilterChipAction(
            spokenName: advice.buttonTitle,
            isActive: { false },
            toggle: { [weak self] in self?.clearForNoResults(advice.action) },
            confirmation: advice.action == .clearFilters ? "Filters cleared" : "Search cleared"
        )
    }
}
