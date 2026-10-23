// SPDX-License-Identifier: MIT
import XCTest

final class ExclusionAndRetentionTests: PestoUITestCase {
    private func openPane(_ pane: String, authenticationGranted: Bool = false) {
        launch(defaults: [
            "hasOnboarded": "true",
            "uitestAuthenticationGranted": authenticationGranted ? "true" : "false"
        ])
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar(pane)).click()
    }

    func test_anAppYouAdd_canBeRemovedAgain() {
        openPane("Privacy")
        let add = element(AccessibilityID.addExcludedAppButton)
        XCTAssertTrue(add.waitForExistence(timeout: 5), "there is no Add App control")
        add.click()
        app.menuItems["Enter Bundle ID\u{2026}"].click()
        let field = app.sheets.firstMatch.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the bundle ID prompt has no text field")
        field.click()
        field.typeText("com.example.scratch")
        app.sheets.firstMatch.buttons["Add"].click()

        let remove = element(AccessibilityID.removeExcludedApp("com.example.scratch"))
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "the added app has no Remove button")
        XCTAssertTrue(
            settingsWindow.staticTexts["Not installed"].exists, "an app that is not installed should say so"
        )
        remove.click()

        XCTAssertFalse(remove.waitForNonExistence(timeout: 5) == false, "the app was not removed")
    }

    func test_aBuiltInPasswordManager_staysExcludedWhenAuthenticationIsRefused() {
        openPane("Privacy")
        let allow = element(AccessibilityID.allowExclusion("com.1password.1password"))
        XCTAssertTrue(allow.waitForExistence(timeout: 5))
        allow.click()
        app.menuItems["For 1 hour"].click()

        let stop = element(AccessibilityID.revokeExclusionAllowance("com.1password.1password"))
        XCTAssertFalse(stop.waitForExistence(timeout: 3), "an allowance started without authentication")
        XCTAssertTrue(allow.exists)
    }

    func test_aBuiltInPasswordManager_canBeAllowed_andStoppedAgain() {
        openPane("Privacy", authenticationGranted: true)
        let allow = element(AccessibilityID.allowExclusion("com.1password.1password"))
        XCTAssertTrue(allow.waitForExistence(timeout: 5), "1Password has no Allow control")
        allow.click()
        app.menuItems["For 1 hour"].click()

        let stop = element(AccessibilityID.revokeExclusionAllowance("com.1password.1password"))
        XCTAssertTrue(stop.waitForExistence(timeout: 10), "the allowance did not start")
        capture("settings-exclusion-allowed", of: settingsWindow)
        stop.click()

        XCTAssertTrue(allow.waitForExistence(timeout: 5), "stopping the allowance did not restore the exclusion")
    }

    func test_historyPickers_offerForever() {
        openPane("Data")
        let age = element(AccessibilityID.settingsChoice("retention", "age"))
        XCTAssertTrue(age.waitForExistence(timeout: 5), "no age picker for history")
        age.click()
        XCTAssertTrue(app.menuItems["Forever"].waitForExistence(timeout: 5), "Forever is not offered")
        app.menuItems["Forever"].click()
        XCTAssertTrue(element(AccessibilityID.settingsChoice("retention", "count")).exists, "no count picker")
    }

    func test_theAllowMenu_offersEveryLength() {
        openPane("Privacy")
        let allow = element(AccessibilityID.allowExclusion("com.1password.1password"))
        XCTAssertTrue(allow.waitForExistence(timeout: 5))
        allow.click()

        for length in ["For 15 minutes", "For 1 hour", "For 4 hours", "Until Pesto quits"] {
            XCTAssertTrue(app.menuItems[length].waitForExistence(timeout: 5), "\(length) is not offered")
        }
    }

    func test_aPasswordManagerRow_doesNotNeedASeparateKeepSwitchOrLengthSetting() {
        openPane("Privacy")
        XCTAssertTrue(element(AccessibilityID.allowExclusion("com.1password.1password")).waitForExistence(timeout: 5))
        XCTAssertFalse(settingsWindow.switches["Also keep what an allowed app hides, such as passwords"].exists)
        XCTAssertFalse(settingsWindow.staticTexts["Allow a password manager for"].exists)
    }
}
