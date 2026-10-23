// SPDX-License-Identifier: MIT
import AppKit
import PestoCore

enum AccessibilityPermission {
    static var isGranted: Bool {
        AccessibilityAccess.isTrusted
    }

    /// The System Settings → Privacy & Security → Accessibility deep link, built once.
    static let settingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")

    /// Opens System Settings → Privacy & Security → Accessibility.
    static func openSystemSettings() {
        if let settingsURL { NSWorkspace.shared.open(settingsURL) }
    }

    /// Prompts the user inline (shows the system dialog) if not yet trusted.
    static func requestWithPrompt() {
        AccessibilityAccess.requestWithPrompt()
    }
}
