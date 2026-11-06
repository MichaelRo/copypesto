// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// A miniature of the shelf on the brand backdrop, drawn on glass or on its plain ground, so the choice shows what
/// it does.
struct ShelfSurfacePreview: View {
    @Environment(\.pestoAccent) private var accent
    @Environment(\.colorScheme) private var scheme
    let surface: ShelfSurface
    let themeRaw: String
    var darkThemeRaw = ""

    private static let shelfHeight: CGFloat = 30
    private static let shelfInset: CGFloat = 10
    private static let shelfRadius: CGFloat = 7

    private var shelfShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: Self.shelfRadius, topTrailingRadius: Self.shelfRadius, style: .continuous
        )
    }

    private var ground: Color {
        let dark = scheme == .dark
        let theme = AppTheme.resolve(light: themeRaw, dark: darkThemeRaw, isDark: dark)
        return Color(hex: theme.groundHex(dark: dark)) ?? Color.opaqueSurface
    }

    var body: some View {
        BrandBackdropView()
            .overlay(alignment: .bottom) {
                shelf.padding(.horizontal, Self.shelfInset)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(5)
            .accessibilityHidden(true)
    }

    private var shelf: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(cardFill)
                    .overlay(alignment: .topLeading) {
                        Circle().fill(accent).frame(width: 3, height: 3).padding(2)
                    }
                    .overlay {
                        let focused = index == 1
                        RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(
                            focused ? accent : Color.primary.opacity(0.14), lineWidth: focused ? 1 : 0.5
                        )
                    }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .frame(height: Self.shelfHeight, alignment: .top)
        .background(background)
        .overlay(shelfShape.strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
    }

    private var cardFill: Color {
        if surface == .solid, scheme == .light { return .white }
        return Color.primary.opacity(0.10)
    }

    @ViewBuilder
    private var background: some View {
        switch surface {
        case .glass:
            shelfShape.fill(.regularMaterial)
                .overlay { ThemeTintLayer(themeRaw: themeRaw, darkThemeRaw: darkThemeRaw).clipShape(shelfShape) }
        case .solid:
            shelfShape.fill(ground)
        }
    }
}
