// SPDX-License-Identifier: MIT
import SwiftUI

/// Liquid Glass background for floating chrome (toasts, popovers, HUDs, result panels) —
/// `.glassEffect()` on macOS 26+, falling back to `adaptiveMaterialBackground(in:)` (which is
/// itself Reduce-Transparency-aware) on macOS 15. Mirrors the `GlassCardModifier` /
/// `GlassChipModifier` pattern already used for cards and chips, generalized for panel chrome
/// that isn't full-bleed content (so glass would only ever leak what it's meant to hide, as on
/// the privacy/NSFW blur overlays — those intentionally stay plain adaptive material).
extension View {
    func glassPanelBackground(in shape: some Shape, interactive: Bool = false) -> some View {
        modifier(GlassPanelBackgroundModifier(shape: AnyShape(shape), interactive: interactive))
    }
}

private struct GlassPanelBackgroundModifier: ViewModifier {
    let shape: AnyShape
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            content.adaptiveMaterialBackground(in: shape)
        }
    }
}
