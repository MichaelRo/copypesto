// SPDX-License-Identifier: MIT
import AppKit

extension AppDelegate {
    /// Pesto lives in the menu bar and has no Dock icon, except while one of its own windows is open: Settings, About
    /// and the first-run window then get a Dock icon and a ⌘-Tab entry, so there is a way back to them from System
    /// Settings or another app.
    func updateActivationPolicy() {
        let hasOpenWindow = [settingsWindow, onboardingWindow, aboutWindow].contains { $0?.isVisible == true }
        NSApp.setActivationPolicy(hasOpenWindow ? .regular : Self.baseActivationPolicy)
    }
}
