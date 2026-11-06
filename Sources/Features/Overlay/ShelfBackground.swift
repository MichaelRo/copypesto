// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The shelf surface (ADR 0035): a plain ground that is the theme's own colour, or Liquid Glass (a material before
/// macOS 26), either carrying a wash of the focused card's source app colour. Reduce Transparency always gives the
/// plain ground; the glass is chrome and never goes on a card.
struct ShelfBackground: View {
    var dominantColor: Color = .clear
    @State private var animatedColor: Color = .clear
    @AppStorage(Setting.appTheme) private var themeRaw: String
    @AppStorage(Setting.appThemeDark) private var darkThemeRaw: String
    @Environment(\.shelfDrawsGlass) private var drawsGlassSetting
    @Environment(\.colorScheme) private var scheme

    private var drawsGlass: Bool {
        drawsGlassSetting ?? false
    }

    var body: some View {
        base
            .overlay { wash }
            .onChange(of: dominantColor) { _, newColor in
                withAnimation(Motion.animation(.smooth(duration: 0.6))) { animatedColor = newColor }
            }
    }

    @ViewBuilder
    private var base: some View {
        if drawsGlass {
            glass.overlay { ThemeTintLayer(themeRaw: themeRaw, darkThemeRaw: darkThemeRaw) }
        } else {
            Rectangle().fill(solidGround)
        }
    }

    @ViewBuilder
    private var glass: some View {
        if #available(macOS 26, *) {
            Rectangle().fill(.clear).glassEffect(.regular, in: .rect)
        } else {
            Rectangle().adaptiveMaterialFill()
        }
    }

    /// The wash of the theme is part of this colour, so what `AppThemeTests` checks is what is drawn.
    private var solidGround: Color {
        let dark = scheme == .dark
        let theme = AppTheme.resolve(light: themeRaw, dark: darkThemeRaw, isDark: dark)
        return Color(hex: theme.groundHex(dark: dark)) ?? Color.opaqueSurface
    }

    private var wash: some View {
        let opacity = ShelfSurface.washOpacities(solid: !drawsGlass)
        return MeshGradient(
            width: 3,
            height: 2,
            points: [[0, 0], [0.5, 0], [1, 0], [0, 1], [0.5, 1], [1, 1]],
            colors: [
                .clear, animatedColor.opacity(opacity[0]), .clear,
                animatedColor.opacity(opacity[1]), .clear, animatedColor.opacity(opacity[2])
            ]
        )
        .allowsHitTesting(false)
    }
}

extension EnvironmentValues {
    /// Whether the shelf is drawn on glass, set once at each shelf root so a card never reads the setting. Nil outside
    /// a
    /// shelf (a snapshot, a preview), where a card keeps its glass-friendly fill.
    @Entry var shelfDrawsGlass: Bool?
}

extension View {
    /// Tells the shelf and its cards which surface is chosen, folding in Reduce Transparency.
    func shelfSurfaceEnvironment() -> some View {
        modifier(ShelfSurfaceEnvironment())
    }
}

private struct ShelfSurfaceEnvironment: ViewModifier {
    @AppStorage(Setting.shelfSurface) private var surfaceRaw: String
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.reduceTransparencyOverride) private var reduceTransparencyOverride

    func body(content: Content) -> some View {
        content.environment(
            \.shelfDrawsGlass,
            ShelfSurface.drawsGlass(
                stored: surfaceRaw, reduceTransparency: reduceTransparencyOverride ?? systemReduceTransparency
            )
        )
    }
}
