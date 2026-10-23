// SPDX-License-Identifier: MIT
import XCTest

final class SettingsReorganisationTests: PestoUITestCase {
    private func openSettings(pane: String) {
        launch(defaults: ["hasOnboarded": "true"])
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar(pane)).click()
    }

    func test_thereAreSevenPanes_andTheOldOnesAreGone() {
        openSettings(pane: "General")

        for pane in ["General", "Appearance", "Privacy", "Shortcuts", "Collections", "Snippets", "Data"] {
            XCTAssertTrue(element(AccessibilityID.settingsSidebar(pane)).exists, "\(pane) missing")
        }
        for gone in ["Capture", "Insights", "AI", "Advanced"] {
            XCTAssertFalse(element(AccessibilityID.settingsSidebar(gone)).exists, "\(gone) should be merged")
        }
    }

    func test_appExclusions_liveInPrivacy_notInGeneral() {
        openSettings(pane: "General")
        XCTAssertFalse(element(AccessibilityID.addExcludedAppButton).exists, "App exclusions are in General")

        element(AccessibilityID.settingsSidebar("Privacy")).click()

        XCTAssertTrue(element(AccessibilityID.addExcludedAppButton).waitForExistence(timeout: 5))
    }

    func test_searchingForAppExclusions_opensPrivacy() {
        openSettings(pane: "General")
        let field = settingsWindow.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("exclusions")

        let result = element(AccessibilityID.settingsSearchResult("App exclusions"))
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.click()

        XCTAssertTrue(
            element(AccessibilityID.addExcludedAppButton).waitForExistence(timeout: 5),
            "search must open the Privacy pane so the setting is visible"
        )
    }

    func test_pinnedClipShortcuts_sayWhenNoneAreSet() {
        openSettings(pane: "Shortcuts")

        XCTAssertTrue(
            settingsWindow.staticTexts["No pinned clip has a shortcut yet."].waitForExistence(timeout: 5),
            "Shortcuts should say that no pinned clip has a shortcut, rather than show an inert note"
        )
    }

    func test_shortcuts_haveAPaneOfTheirOwn_andAccessibilityStaysInGeneral() {
        openSettings(pane: "Shortcuts")

        XCTAssertTrue(
            settingsWindow.staticTexts["Everywhere"].waitForExistence(timeout: 5),
            "the Shortcuts pane should list the shortcuts that work in every app"
        )
        XCTAssertTrue(settingsWindow.staticTexts["On the shelf"].exists, "the shelf keys belong to Shortcuts")
        capture("settings-shortcuts", of: settingsWindow)

        element(AccessibilityID.settingsSidebar("General")).click()

        XCTAssertFalse(settingsWindow.staticTexts["Everywhere"].exists, "General no longer lists shortcuts")
        XCTAssertTrue(settingsWindow.staticTexts["Permissions"].waitForExistence(timeout: 5))
    }
}
