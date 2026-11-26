// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The foot glow behind a widget card's content (ADR 0068): Core's `CardGlow` rising from the foot, as the app's card
/// draws it.
struct WidgetGlow: View {
    let glow: CardGlow

    var body: some View {
        if let color = WidgetPalette.color(glow.hex) {
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
