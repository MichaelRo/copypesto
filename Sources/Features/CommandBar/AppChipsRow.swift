// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The app in front, then the three others copied from most this week; any of them can be switched on to show only
/// that app's clips.
struct AppChipsRow: View {
    @Environment(AppState.self) private var appState: AppState
    let recent: [SourceApp]
    let frontmost: SourceApp?

    private var chips: [SourceApp] {
        AppChips.chips(frontmost: frontmost, recent: recent, ownBundleID: Bundle.main.bundleIdentifier)
    }

    var body: some View {
        ForEach(chips, id: \.bundleID) { app in
            let isActive = appState.appChipFilter.contains(app.bundleID)
            PestoChip(
                label: app.name, icon: "app.badge.checkmark",
                iconImage: SourceIconCache.shared.image(forBundleID: app.bundleID), isActive: isActive,
                collapsesLabel: true
            ) {
                if isActive {
                    appState.appChipFilter.remove(app.bundleID)
                } else {
                    appState.appChipFilter.insert(app.bundleID)
                }
            }
            .help(isActive ? "Showing clips from \(app.name), click to remove" : "Show clips from \(app.name)")
            .accessibilityIdentifier(AccessibilityID.appChip(app.bundleID))
        }
    }
}
