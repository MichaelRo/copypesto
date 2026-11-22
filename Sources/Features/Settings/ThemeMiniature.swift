// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// A small shelf drawn in one theme and one appearance, from the theme's own colours: its ground, its wash and its
/// accent. The theme cards, the light and dark tiles and the preview all draw it, so what a card shows is what the
/// shelf will look like.
struct ThemeShelfMiniature: View {
    struct Metrics {
        let horizontalPadding: CGFloat
        let topPadding: CGFloat
        let bottomPadding: CGFloat
        let cardSpacing: CGFloat
        let cardCornerRadius: CGFloat
        let topInset: CGFloat
        let lineSpacing: CGFloat
        let primaryLineWidth: CGFloat
        let secondaryLineWidth: CGFloat
        let lineHeight: CGFloat
        let bottomInset: CGFloat
        let footSpacing: CGFloat
        let dotSize: CGFloat
        let footLineWidth: CGFloat
        let focusLineWidth: CGFloat
    }

    static func metrics(compact: Bool) -> Metrics {
        if compact {
            Metrics(
                horizontalPadding: 5,
                topPadding: 6,
                bottomPadding: 5,
                cardSpacing: 3,
                cardCornerRadius: 3,
                topInset: 2.5,
                lineSpacing: 1.5,
                primaryLineWidth: 9,
                secondaryLineWidth: 6,
                lineHeight: 1.5,
                bottomInset: 2.5,
                footSpacing: 1.5,
                dotSize: 3,
                footLineWidth: 6,
                focusLineWidth: 1
            )
        } else {
            Metrics(
                horizontalPadding: 12,
                topPadding: 14,
                bottomPadding: 8,
                cardSpacing: 5,
                cardCornerRadius: 5,
                topInset: 5,
                lineSpacing: 2.5,
                primaryLineWidth: 22,
                secondaryLineWidth: 15,
                lineHeight: 2.5,
                bottomInset: 4,
                footSpacing: 3,
                dotSize: 5,
                footLineWidth: 12,
                focusLineWidth: 1.5
            )
        }
    }

    let theme: AppTheme
    let dark: Bool
    var accentOverride: Color?
    var compact = false

    private var accent: Color {
        accentOverride ?? Color(hex: theme.accentHex(dark: dark)) ?? .clear
    }

    private static func ink(_ dark: Bool, _ opacity: Double) -> Color {
        dark ? Color.white.opacity(opacity * 0.75) : Color.black.opacity(opacity * 0.5)
    }

    var body: some View {
        let tint = theme.tint(dark: dark)
        let metrics = Self.metrics(compact: compact)
        let cardShape = RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
        ZStack {
            Color(hex: dark ? BrandPalette.darkSurface : BrandPalette.garlic) ?? .clear
            if let tint, let wash = Color(hex: tint.hex) { wash.opacity(tint.opacity) }
            HStack(spacing: metrics.cardSpacing) {
                ForEach(0..<3, id: \.self) { index in
                    cardShape
                        .fill(dark ? Color.white.opacity(0.13) : Color.black.opacity(0.07))
                        // A card has no header band: its clip drawn as text lines at the top, and at the foot the app's
                        // mark and a line of text.
                        .overlay(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: metrics.lineSpacing) {
                                Capsule().fill(Self.ink(dark, 0.55))
                                    .frame(width: metrics.primaryLineWidth, height: metrics.lineHeight)
                                Capsule().fill(Self.ink(dark, 0.4))
                                    .frame(width: metrics.secondaryLineWidth, height: metrics.lineHeight)
                            }
                            .padding(metrics.topInset)
                        }
                        .overlay(alignment: .bottomLeading) {
                            HStack(spacing: metrics.footSpacing) {
                                Circle().fill(accent).frame(width: metrics.dotSize, height: metrics.dotSize)
                                Capsule().fill(Self.ink(dark, 0.4))
                                    .frame(width: metrics.footLineWidth, height: metrics.lineHeight)
                            }
                            .padding(metrics.bottomInset)
                        }
                        .clipShape(cardShape)
                        .overlay {
                            if index == 1 {
                                cardShape.strokeBorder(accent, lineWidth: metrics.focusLineWidth)
                            }
                        }
                }
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.top, metrics.topPadding)
            .padding(.bottom, metrics.bottomPadding)
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
