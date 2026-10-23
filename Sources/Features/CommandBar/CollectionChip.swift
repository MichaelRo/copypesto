// SPDX-License-Identifier: MIT
import SwiftUI

// MARK: - Glass chip modifier

/// Capsule glass on macOS 26; plain tinted background fallback on earlier systems.
private struct GlassChipModifier: ViewModifier {
    let isSelected: Bool
    let color: Color

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(
                isSelected
                    ? .regular.tint(color.opacity(0.25)).interactive()
                    : .regular.interactive(),
                in: Capsule()
            )
        } else {
            content.background {
                Capsule().fill(isSelected ? color.opacity(0.2) : Color.clear)
            }
        }
    }
}

/// A pinboard selector chip. At rest it shows only the icon/emoji; on hover it expands
/// to reveal the pinboard name. The chip is tinted with the pinboard's color.
struct CollectionChip: View {
    let name: String
    let symbolName: String
    let color: Color
    var isSelected: Bool = false
    /// What VoiceOver says when it should differ from the visible name ("All" is "All collections").
    var spokenName: String?
    var onSelect: (() -> Void)?

    @State private var isHovered = false
    @Environment(\.colorScheme) private var scheme

    /// The collection's color on the glyph only, darkened on a light shelf so it reads at 3:1; the name is primary
    /// text.
    private var glyphColor: Color {
        color.mix(with: scheme == .dark ? .white : .black, by: scheme == .dark ? 0.15 : 0.4)
    }

    var body: some View {
        Button { onSelect?() } label: { chipLabel }
            .buttonStyle(.plain)
            .help(name)
            .accessibilityLabel(spokenName ?? name)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier(AccessibilityID.collectionChip(name))
    }

    private var chipLabel: some View {
        HStack(spacing: 4) {
            CollectionIcon(symbolName: symbolName)
                .font(.callout.weight(.medium))
                .foregroundStyle(glyphColor)

            if isHovered || isSelected {
                Text(name)
                    .scaledFont(size: 12, weight: .medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(.horizontal, isHovered || isSelected ? 10 : 7)
        .padding(.vertical, 5)
        .modifier(GlassChipModifier(isSelected: isSelected, color: color))
        .contentShape(Rectangle())
        .onHover { over in
            withAnimation(Motion.animation(.easeInOut(duration: 0.15))) { isHovered = over }
        }
        .animation(Motion.animation(.easeInOut(duration: 0.15)), value: isHovered)
        .animation(Motion.animation(.easeInOut(duration: 0.15)), value: isSelected)
    }
}
