// SPDX-License-Identifier: MIT
import XCTest

/// Two documentation pictures that cannot come from the stubbed run: the lock screen with the system's own Touch ID
/// view, and Ask Pesto answered by Apple's on-device model. They need a Mac with Touch ID and Apple Intelligence and a
/// person at it, so they run only from `make capture-real` (which sets `TEST_RUNNER_PESTO_REAL_DEVICE_CAPTURE=1`) and
/// are skipped everywhere else, the gate included (`scripts/verify-allowed-skips.txt`).
final class RealDeviceCaptureTests: PestoUITestCase {
    override func setUp() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PESTO_REAL_DEVICE_CAPTURE"] == "1",
            "Run make capture-real on a Mac with Touch ID and Apple Intelligence."
        )
        try await super.setUp()
    }

    func test_lockScreenWithTheSystemTouchIDView() {
        launch(
            seed: "marketing",
            defaults: ["hasOnboarded": "true", "biometricLockEnabled": "true", "appearanceMode": "dark"],
            backdrop: "plain", realDevice: true
        )

        showOverlay(expectingCards: false)

        XCTAssertTrue(element(AccessibilityID.lockOverlay).waitForExistence(timeout: 10), "the lock screen should show")
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        capture("real-history-locked")
    }

    func test_askAnsweredByTheOnDeviceModel() {
        launch(
            seed: "marketing", defaults: ["hasOnboarded": "true", "appearanceMode": "dark"], backdrop: "plain",
            realDevice: true
        )
        showOverlay()
        element(AccessibilityID.searchButton).click()
        XCTAssertTrue(element(AccessibilityID.searchField).waitForExistence(timeout: 5))
        app.typeText("the link from today")
        let ask = element(AccessibilityID.askButton)
        XCTAssertTrue(ask.waitForExistence(timeout: 5))
        ask.click()
        RunLoop.current.run(until: Date().addingTimeInterval(6))
        capture("real-ask")
    }
}
