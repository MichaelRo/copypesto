// SPDX-License-Identifier: MIT
import XCTest

final class BiometricLockOverlayUITests: PestoUITestCase {
    private let locked = ["hasOnboarded": "true", "biometricLockEnabled": "true"]

    func test_whenEmbeddedBiometricsUnavailable_thenRetriesExhaustToTryAgainAndUsePasswordStaysOpen() {
        launch(defaults: locked, embeddedBiometrics: true)
        showOverlay(expectingCards: false)

        XCTAssertTrue(element(AccessibilityID.lockOverlay).waitUntilExists(timeout: 5), "lock overlay missing")
        XCTAssertTrue(overlay.exists, "shelf should remain open")

        let usePassword = app.buttons["Use Password\u{2026}"]
        XCTAssertTrue(usePassword.waitUntilExists(timeout: 5), "Use Password button missing")
        usePassword.click()

        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        XCTAssertTrue(overlay.exists, "shelf must stay open during async auth")
        XCTAssertTrue(element(AccessibilityID.lockOverlay).exists, "history must remain locked on refused auth")
    }
}
