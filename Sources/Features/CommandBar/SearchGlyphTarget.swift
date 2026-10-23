// SPDX-License-Identifier: MIT
import SwiftUI

/// The toolbar glyphs are 16 points; on macOS 26 the glass button style pads them to a target over 24, and under 26 the
/// plain style adds nothing, so the glyph is given its 24 points there (A-10).
struct SearchGlyphTarget: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.frame(width: 16, height: 16)
        } else {
            content.pestoHitTarget()
        }
    }
}
