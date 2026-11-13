// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// A small shelf drawn in one theme and one appearance, from the theme's own colours: its ground, its wash and its
/// accent. The theme cards, the light and dark tiles and the preview all draw it, so what a card shows is what the
/// shelf will look like.
struct ThemeShelfMiniature: View {
    let theme: AppTheme
    let dark: Bool
    var accentOverride: Color?

    private var accent: Color {
        accentOverride ?? Color(hex: theme.accentHex(dark: dark)) ?? .clear
    }

    private static func ink(_ dark: Bool, _ opacity: Double) -> Color {
        dark ? Color.white.opacity(opacity * 0.75) : Color.black.opacity(opacity * 0.5)
    }

    var body: some View {
        let tint = theme.tint(dark: dark)
        ZStack {
            Color(hex: dark ? BrandPalette.darkSurface : BrandPalette.garlic) ?? .clear
            if let tint, let wash = Color(hex: tint.hex) { wash.opacity(tint.opacity) }
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(dark ? Color.white.opacity(0.13) : Color.black.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        // A card has no header (ADR 0044): its line of facts at the foot, an app's mark and a line of
                        // text, and its clip drawn as text lines at the top.
                        .overlay(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 2.5) {
                                Capsule().fill(Self.ink(dark, 0.55)).frame(width: 22, height: 2.5)
                                Capsule().fill(Self.ink(dark, 0.4)).frame(width: 15, height: 2.5)
                            }
                            .padding(5)
                        }
                        .overlay(alignment: .bottomLeading) {
                            HStack(spacing: 3) {
                                Circle().fill(accent).frame(width: 5, height: 5)
                                Capsule().fill(Self.ink(dark, 0.4)).frame(width: 12, height: 2.5)
                            }
                            .padding(4)
                        }
                        .overlay {
                            if index == 1 {
                                RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(
                                    accent,
                                    lineWidth: 1.5
                                )
                            }
                        }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 8)
        }
        .accessibilityHidden(true)
    }
}

/// The lower right half of a rectangle, cut along the diagonal: where a theme card shows its dark side.
struct DiagonalHalf: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The right half of a rectangle: where the System tile shows its dark side.
struct RightHalf: Shape {
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.midX, y: rect.minY, width: rect.width / 2, height: rect.height))
    }
}
