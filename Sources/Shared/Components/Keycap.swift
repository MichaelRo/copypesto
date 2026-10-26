// SPDX-License-Identifier: MIT
import SwiftUI

/// One key as the website draws it: a small rounded cap with a hairline border over a faint fill, in a monospaced
/// face. The card's ⌘N badge, the onboarding shortcut and the "ready" screen all use it.
struct Keycap: View {
    enum Size {
        case compact
        case regular
    }

    enum Style {
        case solid
        case ghost
    }

    let symbol: String
    var size: Size = .regular
    var style: Style = .solid
    /// A compact cap that is audited text (the delete question's hint) gets the solid ground and the primary color of
    /// the regular one; the compact cap on a card keeps the website's faint look.
    var solid = false
    @Environment(\.colorScheme) private var scheme

    private var radius: CGFloat {
        size == .compact ? 5 : 7
    }

    /// A solid fill at the regular size: the accessibility audit cannot measure text over a translucent one. The
    /// compact cap on a card has no text of its own to audit (it is hidden from accessibility) and keeps the website's
    /// faint fill.
    private var fill: Color {
        size == .compact && !solid
            ? Color.white.opacity(scheme == .dark ? 0.08 : 0.55)
            : Color(nsColor: .controlBackgroundColor)
    }

    /// One optical size for every key: a modifier glyph (⇧ ⌥ ⌃) in a monospaced face draws about half the size of ⌘ or
    /// a
    /// letter, so the glyphs use the system face at a weight that matches, and a word or letter stays monospaced.
    private var font: Font {
        let style: Font.TextStyle = size == .compact ? .caption2 : .footnote
        return Self.isModifierGlyph(symbol)
            ? .system(style, design: .default, weight: .semibold)
            : .system(style, design: .monospaced, weight: .semibold)
    }

    static func isModifierGlyph(_ symbol: String) -> Bool {
        symbol.count == 1 && "⌃⌥⇧⌘".contains(symbol)
    }

    var body: some View {
        Text(symbol)
            .font(font)
            .foregroundStyle(size == .compact && !solid ? Color.secondary : Color.primary)
            .padding(.horizontal, size == .compact ? 5 : 7)
            .frame(minWidth: size == .compact ? 0 : 24, minHeight: size == .compact ? 0 : 24)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        style == .ghost ? Color.primary.opacity(0.35) : Color.primary.opacity(0.28),
                        style: style == .ghost ? StrokeStyle(lineWidth: 1, dash: [3, 2]) : StrokeStyle(lineWidth: 1)
                    )
            )
    }
}
