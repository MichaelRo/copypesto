// SPDX-License-Identifier: MIT
import XCTest

/// A Mac with no login password and no Touch ID cannot ask anyone to prove who they are, so what needs that is not
/// offered there (and the lock can still be switched off, so nobody is trapped).
final class AuthenticationUnavailableUITests: PestoUITestCase {
    private func openPrivacy(lockOn: Bool) -> XCUIElement {
        launch(defaults: [
            "hasOnboarded": "true", "biometricLockEnabled": lockOn ? "true" : "false",
            "uitestAuthenticationUnavailable": "true"
        ])
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar("Privacy")).click()
        let toggle = element(AccessibilityID.settingsChoice("historyLock", "toggle"))
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        return toggle
    }

    func test_theLock_isNotOffered_whereNothingCouldUnlockIt() {
        let toggle = openPrivacy(lockOn: false)

        XCTAssertFalse(toggle.isEnabled, "the lock can be switched on where nothing can unlock it")
        XCTAssertTrue(
            element(AccessibilityID.authenticationUnavailable).waitForExistence(timeout: 5),
            "no explanation of why the lock is unavailable"
        )
        capture("authentication-unavailable-settings")
    }

    func test_anExistingLock_canStillBeSwitchedOff() {
        let toggle = openPrivacy(lockOn: true)
        XCTAssertTrue(toggle.isEnabled)

        toggle.click()

        expectation(for: NSPredicate(format: "value == '0' OR value == 0"), evaluatedWith: toggle)
        waitForExpectations(timeout: 5)
    }

    func test_aHiddenClip_hasNoShowAction_whereNothingCanAuthenticate() {
        launch(defaults: ["hasOnboarded": "true", "uitestAuthenticationUnavailable": "true"])
        showOverlay()
        let masked = card(containing: "4242")
        XCTAssertTrue(masked.waitForExistence(timeout: 10), "no masked card on the shelf")

        XCTAssertFalse(element(AccessibilityID.revealHiddenClip).exists, "Show is offered where it cannot work")
        masked.rightClick()
        XCTAssertFalse(app.menuItems["Show"].exists)
        capture("authentication-unavailable-card")
    }
}
