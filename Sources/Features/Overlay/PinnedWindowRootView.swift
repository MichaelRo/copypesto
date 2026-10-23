// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

/// Root view for the always-on-top pinned clipboard panel.
///
/// Shares the same CommandBarView + GridView layout as the main overlay. By default
/// tapping a card auto-pastes into the previously focused app, matching the main
/// overlay's behavior; users who want copy-only staging behavior can opt out via
/// `pinnedWindowAutoPaste` in Settings → General.
struct PinnedWindowRootView: View {
    @Environment(AppState.self) private var appState: AppState
    @State private var focusedDominantColor: Color = .clear
    @AppStorage(Setting.accentColorHex) private var accentColorHex: String
    @AppStorage(Setting.appTheme) private var appThemeRaw: String
    @AppStorage(Setting.appThemeDark) private var appThemeDarkRaw: String
    @AppStorage(Setting.pinnedWindowAutoPaste) private var pinnedWindowAutoPaste: Bool

    /// The panel draws under a transparent title bar, so its window buttons sit on top of the content.
    private static let titlebarClearance: CGFloat = 32

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                CommandBarView()
                    .padding(.horizontal, 16)
                    .padding(.top, Self.titlebarClearance)
                    .padding(.bottom, 8)

                BiometricLockOverlay {
                    GridView(
                        copyOnly: !pinnedWindowAutoPaste,
                        pasteImmediately: pinnedWindowAutoPaste,
                        onFocusChanged: { color, _ in focusedDominantColor = color }
                    )
                }
            }
            .background(ShelfBackground(dominantColor: focusedDominantColor))
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        // Needs a label of its own, as the AppKit panel has in PinnedWindowController.
        .accessibilityLabel("Floating window")
        .accessibilityIdentifier(AccessibilityID.pinnedPanel)
        .pestoAccented(stored: accentColorHex, theme: appThemeRaw, darkTheme: appThemeDarkRaw)
        .modelContainerIfAvailable(appState.historyContainer)
    }
}

private extension View {
    @ViewBuilder
    func modelContainerIfAvailable(_ container: ModelContainer?) -> some View {
        if let container {
            self.modelContainer(container)
        } else {
            self
        }
    }
}
