// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The shelf asking one card to Show (or Hide) itself, the way the menu's Show does: a card owns what it has revealed,
/// so the keyboard shortcut reaches it through this request rather than through the grid. A new token each time, so
/// asking twice for the same card still arrives.
struct ShowRequest: Equatable {
    let itemID: UUID
    let token = UUID()
}

/// Calls `perform` when the shelf asks this card (and no other) to Show or Hide itself.
struct ShowRequestReceiver: ViewModifier {
    let request: ShowRequest?
    let itemID: UUID
    let perform: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: request) { _, new in
            if new?.itemID == itemID { perform() }
        }
    }
}

/// A single click only focuses a card and a double click pastes it (ADR 0009). The single click is a simultaneous
/// gesture, so focus does not wait for the double-click interval.
struct CardClickGestures: ViewModifier {
    @Environment(\.pestoAccent) private var accent
    let onClick: ((ShelfClick) -> Void)?
    /// The floating window stays on screen, so a click that copies or pastes washes the card once to say it happened.
    var isFlashing = false

    func body(content: Content) -> some View {
        content
            .onTapGesture(count: 2) { onClick?(.double) }
            .simultaneousGesture(TapGesture().onEnded { onClick?(.single) })
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(isFlashing ? 0.35 : 0))
                    .allowsHitTesting(false)
                    .animation(Motion.animation(.pestoWash), value: isFlashing)
            }
    }
}
