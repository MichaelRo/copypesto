// SPDX-License-Identifier: MIT
import SwiftUI

/// One chip on the keyboard's top row, drawn with `MobileChipStyle` at 30 pt high. A chip without a title is its
/// symbol alone (the settings gear), and its caller names it for VoiceOver.
struct KeyboardChip: View {
    let title: String?
    let symbolName: String
    let isSelected: Bool
    let isDimmed: Bool
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                CollectionIcon(symbol: symbolName).accessibilityHidden(true)
                if let title { Text(title).lineLimit(1) }
            }
        }
        .buttonStyle(MobileChipStyle(
            isActive: isSelected, tint: tint, isDimmed: isDimmed, chipHeight: 30, touchMinimum: nil
        ))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
