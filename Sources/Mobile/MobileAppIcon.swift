// SPDX-License-Identifier: MIT
import os
import PestoCore
import SwiftUI
import UIKit

/// The Home Screen icon follows the theme while Match App Icon is on (`AppIconMatching`). iOS confirms every change
/// with an alert, so the icon changes once, when the person leaves Settings, not on every theme they look at; turning
/// the switch on applies it at once, because that is a deliberate act.
enum MobileAppIcon {
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "AppIcon")

    @MainActor
    static func applyIfMatching(defaults: UserDefaults = AppDefaults.store) {
        guard defaults.value(for: Setting.matchesAppIcon), UIApplication.shared.supportsAlternateIcons else { return }
        let theme = AppTheme(stored: defaults.value(for: Setting.appTheme))
        let wanted = AppIconMatching.icon(for: theme, matches: true, current: .basil).alternateIconName
        guard UIApplication.shared.alternateIconName != wanted else { return }
        Task {
            do {
                try await UIApplication.shared.setAlternateIconName(wanted)
            } catch {
                logger.error("The app icon did not change: \(String(describing: error), privacy: .public)")
            }
        }
    }
}

struct MobileAppIconToggle: View {
    @AppStorage(Setting.matchesAppIcon) private var matches: Bool

    var body: some View {
        Toggle("Match App Icon", isOn: $matches)
            .onChange(of: matches) { _, on in
                if on { MobileAppIcon.applyIfMatching() }
            }
            .disabled(!UIApplication.shared.supportsAlternateIcons)
    }
}
