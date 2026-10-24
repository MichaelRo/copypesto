// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The app in front, then the three others copied from most this week; any of them can be switched on to show only
/// that app's clips.
struct AppChipsRow: View {
    @Environment(AppState.self) private var appState: AppState
    let recent: [SourceApp]
    let frontmost: SourceApp?
    /// When the user has custom collections on the bar, app chips show only their icon at rest so the collections have
    /// room; when there are no collections, app chips show their names at rest too.
    var collapsesLabels = true

    private var chips: [SourceApp] {
        AppChips.chips(frontmost: frontmost, recent: recent, ownBundleID: Bundle.main.bundleIdentifier)
    }

    var body: some View {
        ForEach(chips, id: \.bundleID) { app in
            let isActive = appState.appChipFilter.contains(app.bundleID)
            PestoChip(
                label: app.name, icon: "app.badge.checkmark",
                iconImage: SourceIconCache.shared.image(forBundleID: app.bundleID), isActive: isActive,
                collapsesLabel: collapsesLabels,
                helpText: isActive
                    ? String(localized: "Showing clips from \(app.name), click to remove")
                    : String(localized: "Show clips from \(app.name)")
            ) {
                if isActive {
                    appState.appChipFilter.remove(app.bundleID)
                } else {
                    appState.appChipFilter.insert(app.bundleID)
                }
            }
            .accessibilityIdentifier(AccessibilityID.appChip(app.bundleID))
        }
    }
}
