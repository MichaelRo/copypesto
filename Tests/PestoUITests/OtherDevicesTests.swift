// SPDX-License-Identifier: MIT
import XCTest

final class OtherDevicesTests: PestoUITestCase {
    func test_whenCopiesFromOtherDevicesAreNotKept_thenSearchOffersNoOtherDevicesChip() {
        launch()
        showOverlay()

        element(AccessibilityID.searchButton).click()

        XCTAssertTrue(element(AccessibilityID.filterChip("Sensitive")).waitForExistence(timeout: 5))
        XCTAssertFalse(element(AccessibilityID.filterChip("Other Devices")).exists)
    }

    func test_whenCopiesFromOtherDevicesAreKept_thenSearchOffersTheOtherDevicesChip() {
        launch(defaults: ["hasOnboarded": "true", "keepsRemoteCopies": "true"])
        showOverlay()

        element(AccessibilityID.searchButton).click()

        let chip = element(AccessibilityID.filterChip("Other Devices"))
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "no Other Devices chip")
        chip.click()
        let deadline = Date().addingTimeInterval(5)
        while cards.firstMatch.exists, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertFalse(cards.firstMatch.exists, "the sample clips were all copied on this Mac")
    }

    func test_whenCopiesFromOtherDevicesAreNotKeptButOneIsInTheHistory_thenSearchStillOffersTheChip() {
        launch(seed: "remote")
        showOverlay()

        element(AccessibilityID.searchButton).click()

        let chip = element(AccessibilityID.filterChip("Other Devices"))
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "an old clip from another device cannot be found")
        chip.click()
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5))
        capture("other-devices-card")
    }

    func test_privacySettings_offerTheToggleOffByDefault() {
        launch()
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar("Privacy")).click()

        let toggle = element(AccessibilityID.settingsChoice("keepsRemoteCopies", "toggle"))

        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "no Keep copies from other devices toggle")
        XCTAssertEqual(toggle.value as? Int, 0, "copies from other devices must be off by default")
    }
}
