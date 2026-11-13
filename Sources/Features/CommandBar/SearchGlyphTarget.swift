// SPDX-License-Identifier: MIT
import SwiftUI

/// The toolbar glyphs are 16 points; `ShelfBarButtonStyle` gives the button its 32 by 24 point capsule, which is also
/// its hit target (A-10).
struct SearchGlyphTarget: ViewModifier {
    func body(content: Content) -> some View {
        content.frame(width: 16, height: 16)
    }
}
