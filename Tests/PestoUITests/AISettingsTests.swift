// SPDX-License-Identifier: MIT
import XCTest

final class AISettingsTests: PestoUITestCase {
    func test_generalPane_hasOneAppleIntelligenceSwitch_andNoApiKeyField() {
        launch(defaults: ["hasOnboarded": "true"])
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar("General")).click()

        let toggle = element(AccessibilityID.settingsChoice("appleIntelligence", "toggle"))
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "no Apple Intelligence switch in General")
        XCTAssertFalse(settingsWindow.secureTextFields.firstMatch.exists, "there is no API key field any more")
        XCTAssertFalse(element(AccessibilityID.settingsSidebar("AI")).exists, "the AI pane should be gone")
        capture("settings-apple-intelligence", of: settingsWindow)
    }

    func test_switchingItOff_isReflectedInTheCardMenuAndSurvivesReopening() {
        launch(defaults: ["hasOnboarded": "true", "appleIntelligenceEnabled": "false"])
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar("General")).click()

        let toggle = element(AccessibilityID.settingsChoice("appleIntelligence", "toggle"))
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? Int, 0, "the switch should read off when the setting is off")
    }
}
