// SPDX-License-Identifier: MIT
import Foundation

/// Which changes of a list of clips are animated, for the Mac's shelf and the iPhone and iPad grid.
public enum ListChangeMotion {
    /// A list change is animated only when it is one the eye can follow: one clip added or removed, a swap of one for
    /// another, or one clip brought to the front. A search, filter or sort rewrites the whole list and must not
    /// animate.
    public static func shouldAnimateChange(from old: [UUID], to new: [UUID]) -> Bool {
        guard abs(old.count - new.count) <= 2, old != new else { return false }
        let before = Set(old)
        let after = Set(new)
        let changed = before.symmetricDifference(after).count
        if changed > 0 { return changed <= 2 }
        guard let first = new.first, old.contains(first) else { return false }
        return Array(new.dropFirst()) == old.filter { $0 != first }
    }
}
