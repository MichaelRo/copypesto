// SPDX-License-Identifier: MIT
import SwiftUI

/// Liquid Glass chrome for iOS floating banners and sticky chrome bars, falling back to an opaque surface under
/// Reduce Transparency.
extension View {
    func mobileGlassChrome(in shape: some Shape, interactive: Bool = false) -> some View {
        modifier(MobileGlassChromeModifier(shape: AnyShape(shape), interactive: interactive))
    }
}

private struct MobileGlassChromeModifier: ViewModifier {
    let shape: AnyShape
    let interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.reduceTransparencyOverride) private var reduceTransparencyOverride

    private var reduceTransparency: Bool {
        reduceTransparencyOverride ?? systemReduceTransparency
    }

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color.opaqueSurface, in: shape)
        } else {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        }
    }
}
