// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// The one small filter/tag chip: a tinted capsule that is a real button with a comfortable target.
struct PestoChip: View {
    @Environment(\.pestoAccent) private var accent
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var systemDifferentiate
    @Environment(\.differentiateWithoutColorOverride) private var differentiateOverride
    let label: String
    var icon: String?
    /// A picture in place of a symbol, such as an app's own icon on a source-app chip.
    var iconImage: NSImage?
    var tint: Color?
    let isActive: Bool
    /// The keyboard is on this chip (Tab in search): it is drawn with a focus ring.
    var hasKeyboardCursor = false
    let action: () -> Void

    private var color: Color {
        tint ?? accent
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                // A shape as well as a colour: a selected chip must not depend on seeing the tint.
                if isActive {
                    Image(systemName: "checkmark").font(.caption2.weight(.bold)).accessibilityHidden(true)
                }
                if let iconImage {
                    Image(nsImage: iconImage)
                        .resizable()
                        .frame(width: 14, height: 14)
                        .accessibilityHidden(true)
                } else if let icon {
                    Image(systemName: icon)
                }
                Text(label)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // A chip is as wide as its label up to 200 points (a collection named with a sentence no longer
                    // pushes the row into the toolbar): an active one, with its check mark, was cut to "Any ti…".
                    .frame(maxWidth: 200)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9)
            .frame(minHeight: 24)
            .background(Capsule().fill(color.opacity(isActive ? 0.25 : 0.1)))
            // At standard contrast the tint alone marks an inactive chip; under
            // Increase Contrast it also gets a border, and its text goes to full opacity, instead
            // of leaning only on a low-opacity fill and dimmed text.
            .overlay(Capsule().strokeBorder(
                isActive ? color.opacity(0.5) : color.opacity(AdaptiveContrast.inactiveOutlineOpacity(
                    contrast: contrast, differentiateWithoutColor: differentiateOverride ?? systemDifferentiate
                )),
                lineWidth: differentiateOverride ?? systemDifferentiate ? 1 : 0.5
            ))
            // Primary text on a light tint of the accent always reads; accent-coloured text could not for every accent.
            .foregroundStyle(isActive || contrast == .increased ? Color.primary : Color.primary.opacity(0.75))
            .contentShape(Capsule())
            .overlay(Capsule().strokeBorder(accent, lineWidth: hasKeyboardCursor ? 2 : 0).padding(-2))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .animation(Motion.animation(.easeInOut(duration: 0.15)), value: isActive)
    }
}
