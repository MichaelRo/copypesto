// SPDX-License-Identifier: MIT
import XCTest

final class ShelfPositionUITests: PestoUITestCase {
    func test_topPosition_theShelfHangsFromTheTopOfTheScreen() {
        launch(defaults: ["hasOnboarded": "true", "shelfPosition": "underNotch"])
        showOverlay()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        let screenHeight = NSScreen.main?.frame.height ?? 900
        XCTAssertLessThan(overlay.frame.minY, screenHeight / 4, "the shelf should sit near the top edge")
        capture("shelf-top")
    }

    func test_appearance_offersPositionTiles_andChoosingTopSelectsIt() {
        launch(defaults: ["hasOnboarded": "true"])
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar("Appearance")).click()

        let bottom = element(AccessibilityID.settingsChoice("shelfPosition", "bottom"))
        let top = element(AccessibilityID.settingsChoice("shelfPosition", "underNotch"))
        XCTAssertTrue(bottom.waitForExistence(timeout: 5), "no Bottom tile")
        XCTAssertTrue(top.exists, "no Top tile")
        XCTAssertTrue(bottom.isSelected, "Bottom should be the default")
        XCTAssertEqual(bottom.frame.width, top.frame.width, accuracy: 1)
        XCTAssertGreaterThanOrEqual(bottom.frame.height, 92, "the tile is the same 112 x 92 picture as Light and Dark")
        capture("settings-shelf-position-bottom", of: settingsWindow)

        top.click()
        expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: top)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(bottom.isSelected)
        capture("settings-shelf-position-top", of: settingsWindow)
    }

    func test_appearance_positionTilesDrawInLightMode_withTopSelected() {
        launch(defaults: ["hasOnboarded": "true", "appearanceMode": "light", "shelfPosition": "underNotch"])
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar("Appearance")).click()

        let top = element(AccessibilityID.settingsChoice("shelfPosition", "underNotch"))
        XCTAssertTrue(top.waitForExistence(timeout: 5), "no Top tile")
        XCTAssertTrue(top.isSelected, "a stored top position should select the Top tile")
        capture("settings-shelf-position-light", of: settingsWindow)
    }

    func test_byDefault_theShelfRestsOnTheBottom() {
        launch()
        showOverlay()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        let screenHeight = NSScreen.main?.frame.height ?? 900
        XCTAssertGreaterThan(overlay.frame.minY, screenHeight / 2, "the shelf should sit in the lower half")
    }
}
