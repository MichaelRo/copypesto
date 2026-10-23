// SPDX-License-Identifier: MIT
import SwiftUI

/// The quiet text on a card (time, size, counts) is the primary color at 70%, about 5:1 on the card fill; the system
/// `.tertiary` measured 1.9:1 and `.secondary` about 3.9:1. Increase Contrast raises it to 90%.
enum AdaptiveContrast {
    static func quietOpacity(for contrast: ColorSchemeContrast) -> Double {
        contrast == .increased ? 0.9 : 0.7
    }

    static func quiet(_ contrast: ColorSchemeContrast) -> Color {
        Color.primary.opacity(quietOpacity(for: contrast))
    }

    /// An inactive chip is told from the page by its tint alone at standard settings. Increase Contrast and
    /// Differentiate
    /// Without Color give it an outline as well, so its edge does not depend on seeing a color.
    static func inactiveOutlineOpacity(contrast: ColorSchemeContrast, differentiateWithoutColor: Bool) -> Double {
        contrast == .increased || differentiateWithoutColor ? 0.4 : 0
    }
}

extension EnvironmentValues {
    /// Preview/test-only override for Differentiate Without Color, which SwiftUI exposes read-only
    /// (see `reduceTransparencyOverride`). Production code never sets it.
    @Entry var differentiateWithoutColorOverride: Bool?
}

private struct PestoQuiet: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.foregroundStyle(AdaptiveContrast.quiet(contrast))
    }
}

extension View {
    /// Quiet text and glyphs: the primary color at 70% (90% with Increase Contrast), which the system's `.secondary`
    /// (3.8:1 on a light ground) and `.tertiary` (1.9:1) are not.
    func pestoQuiet() -> some View {
        modifier(PestoQuiet())
    }
}
