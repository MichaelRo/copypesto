// SPDX-License-Identifier: MIT
import SwiftUI

/// The card's context menu, built when the menu is asked for. `.contextMenu { cardContextMenu }` builds its content in
/// the card's own body, so every body run of every card walked the menu's conditions (picture cards stat the disk, file
/// cards stat up to 50 paths, link and colour cards parse): 11% of a card body in a profile of a collection switch.
/// Inside its own view the same content is built only when SwiftUI evaluates this body.
///
/// The menu reads the card's `@State` through a copy of the card, which SwiftUI does not watch: after Show the menu
/// still
/// said Show. The two flags that change its labels are stored here, so a change makes SwiftUI run the body again.
struct DeferredCardContextMenu: View {
    let card: ClipboardCard
    let isRevealed: Bool
    let isCovered: Bool

    var body: some View {
        card.cardContextMenu
    }
}
