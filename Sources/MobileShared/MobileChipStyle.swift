// SPDX-License-Identifier: MIT
import SwiftUI

/// Pesto's chip on the ground, as the Mac's `PestoChip` draws it: a light wash of the accent (or the collection's
/// color), stronger and outlined when chosen, with a check mark so the choice does not rest on color alone.
struct MobileChipStyle: ButtonStyle {
    let isActive: Bool
    let tint: Color?
    var isDimmed = false
    var chipHeight: CGFloat = 34
    var touchMinimum: CGFloat? = TouchTarget.minimum
    @Environment(\.pestoAccent) private var accent
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        let color = tint ?? accent
        let fill = isActive ? 0.25 : configuration.isPressed ? 0.18 : 0.10
        return configuration.label
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .frame(minHeight: chipHeight)
            .background(Capsule().fill(color.opacity(fill)))
            .overlay(Capsule().strokeBorder(
                color.opacity(isActive ? 0.5 : contrast == .increased ? 0.45 : 0), lineWidth: 0.5
            ))
            .foregroundStyle(isActive || contrast == .increased ? Color.primary : Color.primary.opacity(0.8))
            .opacity(isDimmed ? 0.5 : 1)
            .frame(minWidth: touchMinimum, minHeight: touchMinimum)
            .contentShape(.rect)
    }
}
