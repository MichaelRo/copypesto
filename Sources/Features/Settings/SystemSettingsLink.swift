// SPDX-License-Identifier: MIT
import AppKit

enum SystemSettingsLink {
    /// System Settings at the Apple Account pane, where iCloud and its Keychain are switched on.
    static func openAppleAccount() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings") {
            NSWorkspace.shared.open(url)
        }
    }
}
