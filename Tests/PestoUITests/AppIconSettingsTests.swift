// SPDX-License-Identifier: MIT
import XCTest

final class AppIconSettingsTests: PestoUITestCase {
    private func openAppearance() {
        launch()
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitUntilExists(timeout: 10))
        element(AccessibilityID.settingsSidebar("Appearance")).click()
    }

    /// The icon follows the theme (Match App Icon); there is no second picker of icons.
    func test_appearanceSettings_offerMatchAppIcon_onByDefault() {
        openAppearance()
        let toggle = element(AccessibilityID.matchAppIconToggle)
        XCTAssertTrue(toggle.waitUntilExists(timeout: 5))
        XCTAssertEqual(toggle.value as? Int, 1)
        XCTAssertFalse(element(AccessibilityID.settingsChoice("appIcon", "basil")).exists)
        capture("settings-app-icon", of: settingsWindow)
    }
}
