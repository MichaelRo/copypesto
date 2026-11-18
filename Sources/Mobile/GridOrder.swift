// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// The order the grid shows while the person is looking. A copy moves a clip to the front of the history at once (so
/// sync and the Mac agree), but the card stays where the person's finger was; the grid takes the history's order again
/// when the app comes back to the front, on pull to refresh and when the scope or the search changes. A clip that is
/// new
/// to the grid (a capture, a sync) is shown at the top.
@MainActor
final class GridOrder {
    private var shown: [UUID]?
    private var context: String?

    /// The ids to draw, given the history's current order for `context` (the scope, search text and kind).
    func arrange(_ fresh: [UUID], context: String) -> [UUID] {
        guard let shown, self.context == context else {
            self.shown = fresh
            self.context = context
            return fresh
        }
        let present = Set(fresh)
        let kept = Set(shown)
        let arrivals = fresh.filter { !kept.contains($0) }
        let arranged = arrivals + shown.filter { present.contains($0) }
        self.shown = arranged
        return arranged
    }

    private var lastIDs: [UUID] = []
    private var animates = false

    /// Whether the change to `ids` is one the eye can follow (`ListChangeMotion`); the same answer for the same list,
    /// however often the view is drawn.
    func shouldAnimate(to ids: [UUID]) -> Bool {
        guard ids != lastIDs else { return animates }
        animates = ListChangeMotion.shouldAnimateChange(from: lastIDs, to: ids)
        lastIDs = ids
        return animates
    }

    /// The next arrangement takes the history's order as it is.
    func resort() {
        shown = nil
    }
}
