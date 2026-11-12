// SPDX-License-Identifier: MIT
import SwiftUI

/// The card's context menu, built when the menu is asked for. `.contextMenu { cardContextMenu }` builds its content in
/// the card's own body, so every body run of every card walked the menu's conditions (picture cards stat the disk, file
/// cards stat up to 50 paths, link and colour cards parse): 11% of a card body in a profile of a collection switch.
/// Inside its own view the same content is built only when SwiftUI evaluates this body.
struct DeferredCardContextMenu: View {
    let card: ClipboardCard

    var body: some View {
        card.cardContextMenu
    }
}
