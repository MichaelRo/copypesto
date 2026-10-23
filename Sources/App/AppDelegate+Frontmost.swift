// SPDX-License-Identifier: MIT
import AppKit
import PestoCore

extension AppDelegate {
    /// A test or screenshot run must not read (or show) whichever app the developer has in front.
    func recordFrontmostApp(_ app: NSRunningApplication?) {
        let showsRealApp = LaunchMode.current.usesSystemIntegrations
        // Pesto's own windows are never an app chip (`AppChips`): while one is in front nothing stands for "the app".
        let isPesto = app?.bundleIdentifier == Bundle.main.bundleIdentifier
        appState.frontmostAppBundleID = showsRealApp ? (isPesto ? nil : app?.bundleIdentifier) : "com.apple.Notes"
        appState.frontmostAppName = showsRealApp ? (isPesto ? nil : app?.localizedName) : "Notes"
    }
}
