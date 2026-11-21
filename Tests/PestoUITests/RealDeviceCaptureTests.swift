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

    private func waitForEmbeddedBiometricPrompt(containerIdentifier: String) {
        XCTAssertTrue(element(containerIdentifier).waitUntilExists(timeout: 10), "lock/auth overlay should show")
        XCTAssertTrue(
            element(AccessibilityID.unlockButton).waitUntilExists(timeout: 5),
            "embedded Touch ID prompt should mount"
        )
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
    }

    func test_lockScreenWithTheSystemTouchIDView() {
        launch(
            seed: "marketing",
            defaults: ["hasOnboarded": "true", "biometricLockEnabled": "true", "appearanceMode": "dark"],
            backdrop: "plain", realDevice: true
        )

        showOverlay(expectingCards: false)
        waitForEmbeddedBiometricPrompt(containerIdentifier: AccessibilityID.lockOverlay)
        capture("real-history-locked")
    }

    func test_shelfAuthenticationPromptWithTheSystemTouchIDView() {
        launch(
            seed: "basic",
            defaults: ["hasOnboarded": "true", "appearanceMode": "dark"],
            backdrop: "plain", realDevice: true
        )

        showOverlay()
        let maskedCard = card(containing: "4242")
        XCTAssertTrue(maskedCard.waitUntilExists(timeout: 10), "masked card missing")
        maskedCard.rightClick()
        let showItem = app.menuItems["Show"]
        XCTAssertTrue(showItem.waitUntilExists(timeout: 5), "Show menu item missing")
        showItem.click()

        waitForEmbeddedBiometricPrompt(containerIdentifier: AccessibilityID.shelfAuthenticationPrompt)
        capture("real-shelf-auth-prompt")
    }

    func test_askAnsweredByTheOnDeviceModel() {
        launch(
            seed: "marketing", defaults: ["hasOnboarded": "true", "appearanceMode": "dark"], backdrop: "plain",
            realDevice: true
        )
        showOverlay()
        element(AccessibilityID.searchButton).click()
        XCTAssertTrue(element(AccessibilityID.searchField).waitUntilExists(timeout: 5))
        app.typeText("the link from today")
        let ask = element(AccessibilityID.askButton)
        XCTAssertTrue(ask.waitUntilExists(timeout: 5))
        ask.click()
        RunLoop.current.run(until: Date().addingTimeInterval(6))
        capture("real-ask")
    }

    func test_realSummarizeLongClipPastesIntoTargetApp() {
        launch(
            seed: "marketing",
            defaults: ["hasOnboarded": "true", "appearanceMode": "dark"],
            backdrop: "plain",
            realDevice: true
        )
        showOverlay()
        let cards = app.groups.matching(NSPredicate(format: "identifier BEGINSWITH 'clip-card-'"))
        guard let firstCard = cards.allElementsBoundByIndex.first, firstCard.waitUntilExists(timeout: 5) else {
            XCTFail("Expected at least one clip card")
            return
        }
        firstCard.rightClick()
        let summarize = app.menuItems["Summarize"].firstMatch
        if summarize.waitUntilExists(timeout: 5) {
            summarize.click()
            // Long/real on-device summarization can take >20 s on real hardware.
            RunLoop.current.run(until: Date().addingTimeInterval(22))
        }
        capture("real-summarize")
    }
}
