// SPDX-License-Identifier: MIT
import os
import PestoCore
import SwiftUI
import UIKit

/// Settings → Appearance → App Icon: the four theme icons (ADR 0013). It is chosen on its own and never follows the
/// theme, because iOS confirms every icon change with an alert the person did not ask for.
struct MobileAppIconPicker: View {
    @State private var choice = AppIconChoice(alternateIconName: UIApplication.shared.alternateIconName)
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "AppIcon")

    var body: some View {
        Picker("App Icon", selection: $choice) {
            ForEach(AppIconChoice.allCases, id: \.self) { option in
                Text(verbatim: option.displayName).tag(option)
            }
        }
        .disabled(!UIApplication.shared.supportsAlternateIcons)
        .onChange(of: choice) { _, new in
            guard UIApplication.shared.alternateIconName != new.alternateIconName else { return }
            Task {
                do {
                    try await UIApplication.shared.setAlternateIconName(new.alternateIconName)
                } catch {
                    Self.logger.error("The app icon did not change: \(String(describing: error), privacy: .public)")
                    choice = AppIconChoice(alternateIconName: UIApplication.shared.alternateIconName)
                }
            }
        }
    }
}
