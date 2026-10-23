// SPDX-License-Identifier: MIT
import PestoCore

/// One search filter chip as the keyboard sees it.
struct FilterChipAction {
    let spokenName: String
    let isActive: () -> Bool
    let toggle: () -> Void
}

extension AppState {
    /// Tab (`delta` 1) and Shift-Tab (-1) in search. Returns false when there are no chips, so the key goes on.
    @discardableResult
    func moveFilterChipCursor(by delta: Int) -> Bool {
        guard !filterChipActions.isEmpty else { return false }
        filterChipCursor = FilterChipCursor.moved(from: filterChipCursor, by: delta, count: filterChipActions.count)
        if let cursor = filterChipCursor {
            let chip = filterChipActions[cursor]
            Announcer.announce("\(chip.spokenName), \(chip.isActive() ? "on" : "off")")
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
        Announcer.announce("\(chip.spokenName), \(chip.isActive() ? "on" : "off")")
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
