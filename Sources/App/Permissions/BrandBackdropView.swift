// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The garlic-into-parmesan ground with a basil glow low on the left and a gold one high on the right: the website's
/// hero backdrop, behind the picture on Pesto's first onboarding screen. Content, not chrome: it goes behind a
/// picture, never behind text (the accessibility audit cannot measure text on a gradient) or the shelf's glass.
/// Plain under Reduce Transparency and Increase Contrast.
struct BrandBackdropView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if reduceTransparency || contrast == .increased {
            Color(nsColor: .windowBackgroundColor)
        } else {
            let dark = scheme == .dark
            let basil = BrandBackdrop.basilGlow
            let gold = BrandBackdrop.goldGlow
            let strength = dark ? 0.5 : 1.0
            ZStack {
                LinearGradient(
                    colors: BrandBackdrop.stops(dark: dark).map { Color(hex: $0) ?? .clear },
                    startPoint: .top, endPoint: .bottom
                )
                RadialGradient(
                    colors: [(Color(hex: basil.hex) ?? .clear).opacity(basil.opacity * strength), .clear],
                    center: UnitPoint(x: 0.18, y: 1), startRadius: 0, endRadius: 520
                )
                RadialGradient(
                    colors: [(Color(hex: gold.hex) ?? .clear).opacity(gold.opacity * strength), .clear],
                    center: UnitPoint(x: 0.88, y: 0.08), startRadius: 0, endRadius: 360
                )
            }
            .accessibilityHidden(true)
        }
    }
}
