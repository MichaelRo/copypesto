// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// Gives every hosted window the user's accent, so panels that do not set it themselves (the paste-stack HUD, the AI
/// result panel, the quick menu) match the shelf.
private struct AccentedRoot<Content: View>: View {
    @AppStorage(Setting.accentColorHex) private var accentColorHex: String
    @AppStorage(Setting.appTheme) private var appThemeRaw: String
    @AppStorage(Setting.appThemeDark) private var appThemeDarkRaw: String
    let content: Content

    var body: some View {
        content.pestoAccented(stored: accentColorHex, theme: appThemeRaw, darkTheme: appThemeDarkRaw)
    }
}

extension SafeHostingView {
    /// The only way to host Pesto UI: every @AppStorage in the hosted tree reads the store chosen by
    /// AppDefaults (private suite under test), instead of silently binding to the real preferences.
    convenience init(pesto rootView: some View) {
        self.init(erasing: Self.pestoRoot(rootView))
    }

    /// Replaces the hosted view and keeps the accent and the preferences store of `init(pesto:)`.
    func setPestoRoot(_ rootView: some View) {
        self.rootView = AnyView(Self.pestoRoot(rootView))
    }

    private static func pestoRoot(_ rootView: some View) -> some View {
        AccentedRoot(content: rootView).defaultAppStorage(AppDefaults.store)
    }
}
