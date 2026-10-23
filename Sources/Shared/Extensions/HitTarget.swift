// SPDX-License-Identifier: MIT
import SwiftUI

extension View {
    /// An icon-only control is at least 24 × 24 points to hit (WCAG 2.2, target size minimum), however small its glyph.
    func pestoHitTarget(_ side: CGFloat = 24) -> some View {
        frame(minWidth: side, minHeight: side).contentShape(Rectangle())
    }
}
