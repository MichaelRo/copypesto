// SPDX-License-Identifier: MIT
import XCTest

final class AppIconSettingsTests: PestoUITestCase {
    private func openAppearance() {
        launch()
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar("Appearance")).click()
    }

    func test_appearanceSettings_offerFourAppIcons_withBasilChosen() {
        openAppearance()

        for name in ["basil", "parmesan", "pineNut", "mortar"] {
            XCTAssertTrue(
                element(AccessibilityID.settingsChoice("appIcon", name)).waitForExistence(timeout: 5),
                "no \(name) icon in Appearance"
            )
        }
        XCTAssertTrue(element(AccessibilityID.settingsChoice("appIcon", "basil")).isSelected)
    }

    /// Each icon is named after its theme, so the icons run in the order of the themes above them.
    func test_theIcons_runInTheOrderOfTheThemes() {
        openAppearance()
        let themes = ["basil", "parmesan", "pineNut", "mortar"]
        let icons = themes
        let themeX = themes.map { element(AccessibilityID.settingsChoice("theme", $0)).frame.minX }
        let iconX = icons.map { element(AccessibilityID.settingsChoice("appIcon", $0)).frame.minX }

        XCTAssertEqual(themeX, themeX.sorted(), "the themes are not left to right")
        XCTAssertEqual(iconX, iconX.sorted(), "the icons are not in the order of the themes")
    }

    func test_choosingAnIcon_selectsIt() {
        openAppearance()
        let mortar = element(AccessibilityID.settingsChoice("appIcon", "mortar"))
        XCTAssertTrue(mortar.waitForExistence(timeout: 5))

        mortar.click()

        let deadline = Date().addingTimeInterval(5)
        while !mortar.isSelected, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertTrue(mortar.isSelected)
        XCTAssertFalse(element(AccessibilityID.settingsChoice("appIcon", "basil")).isSelected)
        capture("settings-app-icon", of: settingsWindow)
    }
}
