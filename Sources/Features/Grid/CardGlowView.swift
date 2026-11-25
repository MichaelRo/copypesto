// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The foot glow on a Mac card (ADR 0068): Core's `CardGlow` rising from the foot, over the card's fill and under its
/// content. Nothing when the card has none.
struct CardGlowView: View {
    let glow: CardGlow?

    var body: some View {
        if let glow, let color = Color(hex: glow.hex) {
            LinearGradient(
                stops: CardGlow.stops
                    .map { .init(color: color.opacity(glow.opacity * $0.share), location: $0.location) },
                startPoint: .bottom, endPoint: .top
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
