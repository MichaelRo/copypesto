// SPDX-License-Identifier: MIT
import SwiftUI

/// The toolbar's last two buttons: the floating window (offered from the shelf only, so it is found without knowing
/// the shortcut) and Settings.
struct ShelfWindowButtons: View {
    @Environment(AppState.self) private var appState: AppState

    var body: some View {
        if appState.isOverlayVisible {
            Button {
                appState.openFloatingWindowFromOverlay?()
            } label: {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 13))
                    .modifier(SearchGlyphTarget())
                    .pestoQuiet()
            }
            .modifier(SearchButtonStyle())
            .help("Open the floating window, a shelf that stays on screen")
            .accessibilityLabel("Floating window")
            .accessibilityIdentifier(AccessibilityID.floatingWindowButton)
        }

        Button {
            appState.openSettingsFromOverlay?()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 13))
                .modifier(SearchGlyphTarget())
                .pestoQuiet()
        }
        .modifier(SearchButtonStyle())
        .help("Settings")
        .accessibilityLabel("Settings")
        .accessibilityIdentifier(AccessibilityID.settingsButton)
    }
}
