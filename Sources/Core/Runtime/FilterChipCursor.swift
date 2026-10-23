// SPDX-License-Identifier: MIT
import Foundation

/// Where the keyboard is in the search filter bar. Without Full Keyboard Access a chip cannot be reached by Tab, so Tab
/// in search walks the chips itself: the first Tab goes to the first chip, and Tab past the last (or Shift-Tab before
/// the first) hands the keyboard back to the search field, which is `nil`.
public enum FilterChipCursor {
    public static func moved(from current: Int?, by delta: Int, count: Int) -> Int? {
        guard count > 0, delta != 0 else { return current.flatMap { $0 < count ? $0 : nil } }
        guard let current else { return delta > 0 ? 0 : count - 1 }
        let next = current + delta
        return (0..<count).contains(next) ? next : nil
    }

    /// The chips can change under the cursor (a source app appears or goes); a cursor past the end is dropped.
    public static func kept(_ current: Int?, count: Int) -> Int? {
        current.flatMap { (0..<count).contains($0) ? $0 : nil }
    }
}
