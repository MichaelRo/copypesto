// SPDX-License-Identifier: MIT
import XCTest

final class BrandAccentTests: PestoUITestCase {
    private func openAppearance() {
        launch(defaults: ["hasOnboarded": "true"])
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar("Appearance")).click()
    }

    func test_aFreshInstall_usesThePestoGreenAccent() {
        openAppearance()
        let brand = element(AccessibilityID.settingsChoice("accent", "brand"))
        XCTAssertTrue(brand.waitForExistence(timeout: 5), "no Pesto green swatch")
        XCTAssertTrue(brand.isSelected, "the brand accent should be the default")
        capture("settings-appearance-brand", of: settingsWindow)
    }

    func test_choosingBlue_movesTheSelection_namesIt_andBackAgain() {
        openAppearance()
        let blue = element(AccessibilityID.settingsChoice("accent", "blue"))
        blue.click()
        expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: blue)
        waitForExpectations(timeout: 5)
        let name = element(AccessibilityID.settingsChoice("accent", "name"))
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual("\(name.value ?? name.label)", "Blue", "the chosen colour is not named under the row")

        element(AccessibilityID.settingsChoice("accent", "brand")).click()
        expectation(
            for: NSPredicate(format: "isSelected == true"),
            evaluatedWith: element(AccessibilityID.settingsChoice("accent", "brand"))
        )
        waitForExpectations(timeout: 5)
    }

    func test_theCustomSwatch_isRoundLikeThePresets() {
        openAppearance()
        let preset = element(AccessibilityID.settingsChoice("accent", "blue"))
        let custom = element(AccessibilityID.settingsChoice("accent", "custom"))
        XCTAssertTrue(custom.waitForExistence(timeout: 5), "no custom swatch")
        XCTAssertEqual(
            custom.frame.width,
            preset.frame.width,
            accuracy: 1,
            "the custom swatch is not the preset's size"
        )
        XCTAssertEqual(custom.frame.height, preset.frame.height, accuracy: 1)
        XCTAssertFalse(custom.isSelected, "the custom swatch is selected while a preset is")
        capture("settings-appearance-accent-row", of: settingsWindow)
    }

    func test_theColourPanel_opensForOther_andClosesWhenAPresetIsChosen() {
        openAppearance()
        element(AccessibilityID.settingsChoice("accent", "custom")).click()
        let panel = app.windows["Colors"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "Other did not open the colour panel")

        element(AccessibilityID.settingsChoice("accent", "purple")).click()

        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: panel)
        waitForExpectations(timeout: 5)
    }
}
