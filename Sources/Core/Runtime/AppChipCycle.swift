// SPDX-License-Identifier: MIT
import Foundation

/// The app filter one ⌥⌘[ or ⌥⌘] press moves to: no filter, then each chip in the order the row shows them, then no
/// filter again. A filter of several chips moves on from its last (forward) or first (backward) chip on the row; apps
/// that are no longer on the row do not count, and a filter made only of them starts over.
public enum AppChipCycle {
    public static func next(current: Set<String>, chips: [String], forward: Bool) -> Set<String> {
        let selected = chips.indices.filter { current.contains(chips[$0]) }
        let target = forward ? (selected.last ?? -1) + 1 : (selected.first ?? chips.count) - 1
        return chips.indices.contains(target) ? [chips[target]] : []
    }
}
