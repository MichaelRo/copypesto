// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The shelf's ground in a Settings picture, as the real shelf draws it: the theme's own colour, or glass with the
/// theme's wash when Glass is chosen and Reduce Transparency is off. The picture's root asks for
/// `shelfSurfaceEnvironment()`; with no answer (a snapshot) it draws glass, as the pictures always did.
struct PreviewShelfFill<ShelfShape: Shape>: View {
    let shape: ShelfShape
    let themeRaw: String
    var darkThemeRaw = ""
    @Environment(\.shelfDrawsGlass) private var drawsGlass
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if drawsGlass ?? true {
            shape.fill(.regularMaterial)
                .overlay { ThemeTintLayer(themeRaw: themeRaw, darkThemeRaw: darkThemeRaw).clipShape(shape) }
        } else {
            shape.fill(solidGround)
        }
    }

    private var solidGround: Color {
        let dark = scheme == .dark
        let theme = AppTheme.resolve(light: themeRaw, dark: darkThemeRaw, isDark: dark)
        return Color(hex: theme.groundHex(dark: dark)) ?? Color.opaqueSurface
    }
}
