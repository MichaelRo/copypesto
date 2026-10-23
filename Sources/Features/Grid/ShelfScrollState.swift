// SPDX-License-Identifier: MIT
import Foundation
import Observation

struct ShelfScrollRequest: Equatable {
    let id: UUID
    let animated: Bool
    let token = UUID()
}

/// What every card on the shelf needs to know that is not about the card itself: whether the shelf is scrolling,
/// whether
/// the pointer has moved since it opened, the animated-image setting and whether a menu is open. It is its own object
/// so that one of these changing updates only the cards that read it, not the whole grid view and every card with it,
/// and so each card does not hold its own notification subscriptions.
@MainActor
@Observable
final class ShelfScrollState {
    var isScrolling = false
    var pointerHasMoved = false
    var autoPlayAllowed = AnimatedImageSettings.autoPlayAllowed
    private(set) var menuOpenings = 0

    func menuOpened() {
        menuOpenings += 1
    }

    func refreshAutoPlay() {
        let allowed = AnimatedImageSettings.autoPlayAllowed
        if autoPlayAllowed != allowed { autoPlayAllowed = allowed }
    }
}
