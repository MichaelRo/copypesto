// SPDX-License-Identifier: MIT
import SwiftUI

/// One chip on the keyboard's top row, drawn like the Mac shelf's chips: a capsule with a glyph and a name, filled
/// with the accent when chosen.
struct KeyboardChip: View {
    let title: String
    let symbolName: String
    let isSelected: Bool
    let isDimmed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbolName)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                // The accent is dark green in Light and light green in Dark: the ground's color reads on both.
                .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : Color.primary)
                .background(
                    isSelected ? BrandAccent.color : Color.primary.opacity(0.08),
                    in: Capsule()
                )
                .opacity(isDimmed ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
