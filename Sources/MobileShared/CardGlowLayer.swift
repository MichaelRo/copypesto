// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The foot glow drawn behind a card's content and over its fill (ADR 0068): Core's `CardGlow` rising from the foot.
/// `reach` stretches the stops for a short card (the keyboard's), where 40% of the height is too little to read.
struct CardGlowLayer: View {
    let glow: CardGlow?
    var reach = 1.0

    var body: some View {
        if let glow, let color = Color(hex: glow.hex) {
            LinearGradient(
                stops: CardGlow.stops.map { stop in
                    .init(color: color.opacity(glow.opacity * stop.share), location: min(stop.location * reach, 1))
                },
                startPoint: .bottom, endPoint: .top
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Faces that carry their own color or a picture keep it: the glow is for faces drawn on the card's fill.
    static func shows(on face: CardFace) -> Bool {
        switch face {
        case .text, .largeText, .code, .link, .file, .shownSecret: true
        case .picture, .linkPicture, .color, .covered: false
        }
    }
}
