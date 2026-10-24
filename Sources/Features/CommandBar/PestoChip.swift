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
    /// When true (shelf app chips), shows only the icon at rest and opens the label on hover, keyboard focus or
    /// selection.
    var collapsesLabel = false
    let action: () -> Void

    @State private var isHovered = false

    private var color: Color {
        tint ?? accent
    }

    private var isLabelVisible: Bool {
        !collapsesLabel || isActive || isHovered || hasKeyboardCursor
    }

    private var fillOpacity: Double {
        if isActive { return 0.25 }
        return isHovered ? 0.18 : 0.10
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                // A shape as well as a colour: a selected chip must not depend on seeing the tint.
                if isActive, !collapsesLabel {
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
                if isLabelVisible {
                    Text(label)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        // A chip is as wide as its label up to 200 points (a collection named with a sentence no longer
                        // pushes the row into the toolbar): an active one, with its check mark, was cut to "Any ti…".
                        .frame(maxWidth: 200)
                        .fixedSize(horizontal: true, vertical: false)
                    if isActive, collapsesLabel {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .accessibilityHidden(true)
                    }
                }
            }
            .font(.caption.weight(.medium))
            .padding(.leading, collapsesLabel ? 5 : 9)
            .padding(.trailing, collapsesLabel && !isLabelVisible ? 5 : 9)
            .frame(minWidth: 24, minHeight: 24)
            .fixedSize(horizontal: true, vertical: false)
            .background(Capsule().fill(color.opacity(fillOpacity)))
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
            .foregroundStyle(isActive || isHovered || contrast == .increased ? Color.primary : Color.primary
                .opacity(0.75))
            .contentShape(Capsule())
            .overlay(Capsule().strokeBorder(accent, lineWidth: hasKeyboardCursor ? 2 : 0).padding(-2))
        }
        .buttonStyle(.plain)
        .onHover { over in
            withAnimation(Motion.animation(.pestoQuick)) { isHovered = over }
        }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityValue(collapsesLabel && isActive ? "selected" : "")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .animation(Motion.animation(.pestoQuick), value: isLabelVisible)
        .animation(Motion.animation(.pestoQuick), value: isActive)
    }
}
