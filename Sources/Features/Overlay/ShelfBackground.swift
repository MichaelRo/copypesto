// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The shelf surface: Liquid Glass (a material before macOS 26) carrying a faint wash of the focused card's source
/// app colour. Glass, not a hand-drawn dark fill, so Light mode, Reduce Transparency and the system transparency
/// setting all behave.
struct ShelfBackground: View {
    var dominantColor: Color = .clear
    @State private var animatedColor: Color = .clear
    @AppStorage(Setting.appTheme) private var themeRaw: String
    @AppStorage(Setting.appThemeDark) private var darkThemeRaw: String

    var body: some View {
        surface
            .overlay { ThemeTintLayer(themeRaw: themeRaw, darkThemeRaw: darkThemeRaw) }
            .overlay { wash }
            .onChange(of: dominantColor) { _, newColor in
                withAnimation(Motion.animation(.smooth(duration: 0.6))) { animatedColor = newColor }
            }
    }

    @ViewBuilder
    private var surface: some View {
        if #available(macOS 26, *) {
            Rectangle().fill(.clear).glassEffect(.regular, in: .rect)
        } else {
            Rectangle().adaptiveMaterialFill()
        }
    }

    private var wash: some View {
        MeshGradient(
            width: 3,
            height: 2,
            points: [[0, 0], [0.5, 0], [1, 0], [0, 1], [0.5, 1], [1, 1]],
            colors: [
                .clear, animatedColor.opacity(0.22), .clear,
                animatedColor.opacity(0.12), .clear, animatedColor.opacity(0.18)
            ]
        )
        .allowsHitTesting(false)
    }
}
