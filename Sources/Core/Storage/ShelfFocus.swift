// SPDX-License-Identifier: MIT
import Foundation

/// Where the shelf's focus ring belongs after the clips changed. The ring follows its clip, so a copy that arrives
/// while the shelf is open does not make Return paste a different card than the one that was highlighted.
public enum ShelfFocus {
    public static func resolvedIndex(focusedID: UUID?, previousIndex: Int, in ids: [UUID]) -> Int {
        guard !ids.isEmpty else { return 0 }
        guard previousIndex > 0 else { return 0 }
        if let focusedID, let index = ids.firstIndex(of: focusedID) { return index }
        return min(previousIndex, ids.count - 1)
    }
}
