// SPDX-License-Identifier: MIT
import SwiftUI

/// A collection selector chip in the shelf's command bar. Uses the same 24 pt tinted capsule geometry as `PestoChip`
/// and always shows its icon and collection name (while app chips show only their icon at rest and expand on hover).
struct CollectionChip: View {
    @Environment(\.pestoAccent) private var accent
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var systemDifferentiate
    @Environment(\.differentiateWithoutColorOverride) private var differentiateOverride

    let name: String
    let symbolName: String
    let color: Color
    var isSelected: Bool = false
    /// What VoiceOver says when it should differ from the visible name ("All" is "All collections").
    var spokenName: String?
    var onSelect: (() -> Void)?

    @State private var isHovered = false
    @FocusState private var isKeyboardFocused: Bool

    private var tintColor: Color {
        color == .primary ? accent : color
    }

    /// The collection's color on the glyph only, darkened on a light shelf so it reads at 3:1; the name is primary
    /// text.
    private var glyphColor: Color {
        tintColor.mix(with: scheme == .dark ? .white : .black, by: scheme == .dark ? 0.15 : 0.4)
    }

    private var fillOpacity: Double {
        if isSelected { return 0.25 }
        return isHovered ? 0.18 : 0.10
    }

    var body: some View {
        Button { onSelect?() } label: { chipLabel }
            .buttonStyle(.plain)
            .focused($isKeyboardFocused)
            .focusEffectDisabled()
            .onHover { over in
                withAnimation(Motion.animation(.pestoQuick)) { isHovered = over }
            }
            .help(name)
            .accessibilityLabel(spokenName ?? name)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier(AccessibilityID.collectionChip(name))
            .animation(Motion.animation(.pestoQuick), value: isSelected)
    }

    private var chipLabel: some View {
        HStack(spacing: 4) {
            CollectionIcon(symbolName: symbolName)
                .foregroundStyle(glyphColor)

            Text(name)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 200)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 9)
        .frame(minWidth: 24, minHeight: 24)
        .fixedSize(horizontal: true, vertical: false)
        .background(Capsule().fill(tintColor.opacity(fillOpacity)))
        .overlay(Capsule().strokeBorder(
            isSelected ? tintColor.opacity(0.5) : tintColor.opacity(AdaptiveContrast.inactiveOutlineOpacity(
                contrast: contrast, differentiateWithoutColor: differentiateOverride ?? systemDifferentiate
            )),
            lineWidth: differentiateOverride ?? systemDifferentiate ? 1 : 0.5
        ))
        .foregroundStyle(
            isSelected || isHovered || isKeyboardFocused || contrast == .increased
                ? Color.primary
                : Color.primary.opacity(0.75)
        )
        .contentShape(Capsule())
        .overlay(Capsule().strokeBorder(accent, lineWidth: isKeyboardFocused ? 2 : 0).padding(-2))
    }
}
