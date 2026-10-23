// SPDX-License-Identifier: MIT
import XCTest

final class HistoryLockSettingsTests: PestoUITestCase {
    private func openPrivacy(authenticationGranted: Bool) -> XCUIElement {
        launch(defaults: [
            "hasOnboarded": "true", "biometricLockEnabled": "true",
            "uitestAuthenticationGranted": authenticationGranted ? "true" : "false"
        ])
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar("Privacy")).click()
        let toggle = element(AccessibilityID.settingsChoice("historyLock", "toggle"))
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        return toggle
    }

    private func isOn(_ toggle: XCUIElement) -> Bool {
        (toggle.value as? String) == "1" || (toggle.value as? Int) == 1
    }

    func test_turningTheLockOff_needsAuthentication() {
        let toggle = openPrivacy(authenticationGranted: false)
        XCTAssertTrue(isOn(toggle), "the lock should start on")

        toggle.click()
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))

        XCTAssertTrue(isOn(toggle), "the lock switched off without authentication")
    }

    func test_turningTheLockOff_worksAfterAuthentication() {
        let toggle = openPrivacy(authenticationGranted: true)
        XCTAssertTrue(isOn(toggle))

        toggle.click()

        expectation(for: NSPredicate(format: "value == '0' OR value == 0"), evaluatedWith: toggle)
        waitForExpectations(timeout: 5)
    }
}
