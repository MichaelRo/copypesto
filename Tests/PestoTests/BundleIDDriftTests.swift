// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("BundleIDDrift")
struct BundleIDDriftTests {
    @Test("Passwords.app and its menu bar extra login item bundle IDs are in defaultExcludedBundleIDs")
    func whenPasswordsBundlesInspected_thenExcludedByDefault() throws {
        let passwordsApp = URL(fileURLWithPath: "/System/Applications/Passwords.app")
        let passwordsBundle = try #require(Bundle(url: passwordsApp))
        let passwordsID = try #require(passwordsBundle.bundleIdentifier)
        #expect(ExclusionRules.defaultExcludedBundleIDs.contains(passwordsID))

        let menuBarExtraApp = passwordsApp
            .appendingPathComponent("Contents/Library/LoginItems/PasswordsMenuBarExtra.app")
        let menuBarBundle = try #require(Bundle(url: menuBarExtraApp))
        let menuBarID = try #require(menuBarBundle.bundleIdentifier)
        #expect(ExclusionRules.defaultExcludedBundleIDs.contains(menuBarID))
    }

    @Test("1Password.app bundle ID is in defaultExcludedBundleIDs when installed")
    func whenOnePasswordInstalled_thenExcludedByDefault() throws {
        let onePasswordPath = "/Applications/1Password.app"
        guard FileManager.default.fileExists(atPath: onePasswordPath) else { return }
        let bundle = try #require(Bundle(url: URL(fileURLWithPath: onePasswordPath)))
        let bundleID = try #require(bundle.bundleIdentifier)
        #expect(ExclusionRules.defaultExcludedBundleIDs.contains(bundleID))
    }
}
