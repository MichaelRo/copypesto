// SPDX-License-Identifier: MIT
import UIKit
import XCTest

/// The iPhone pass for the History Lock and the content cover (ADR 0054): the lock screen draws no card, and Hide Clip
/// Contents covers every card until one is shown.
@MainActor
final class PrivacyUITests: XCTestCase {
    private let timeout: TimeInterval = 15

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "the iPhone pass")
    }

    private func launch(environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["PESTO_UITEST_SESSION"] = "mobile-\(UUID().uuidString)"
        app.launchEnvironment["PESTO_UITEST_SEED"] = "basic"
        for (key, value) in environment {
            app.launchEnvironment[key] = value
        }
        app.launch()
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func test_whenTheLockIsOn_thenTheLaunchShowsTheLockScreenAndNoCard() {
        let refused = launch(environment: [
            "PESTO_UITEST_DEFAULT_biometricLockEnabled": "true",
            "PESTO_UITEST_DEFAULT_uitestAuthenticationGranted": "false"
        ])
        XCTAssertTrue(element(MobileAccessibilityID.lockScreen, in: refused).waitForExistence(timeout: timeout))
        let unlock = element(MobileAccessibilityID.unlockButton, in: refused)
        XCTAssertTrue(unlock.waitForExistence(timeout: timeout))
        XCTAssertFalse(element(MobileAccessibilityID.clipCard, in: refused).exists, "no card is drawn while locked")
        capture("Lock screen")
        unlock.tap()
        XCTAssertTrue(element(MobileAccessibilityID.lockScreen, in: refused).waitForExistence(timeout: 2))
        XCTAssertFalse(element(MobileAccessibilityID.clipCard, in: refused).exists, "a refused prompt keeps it locked")
        refused.terminate()

        let granted = launch(environment: [
            "PESTO_UITEST_DEFAULT_biometricLockEnabled": "true",
            "PESTO_UITEST_DEFAULT_uitestAuthenticationGranted": "true"
        ])
        XCTAssertTrue(
            element(MobileAccessibilityID.clipCard, in: granted).waitForExistence(timeout: timeout),
            "the lock screen asks by itself and the library opens"
        )
        XCTAssertFalse(element(MobileAccessibilityID.lockScreen, in: granted).exists)
    }

    func test_whenClipContentsAreHiddenByHand_thenCardsSayOnlyTheirKind() {
        let app = launch()
        let packing = app.descendants(matching: .any).matching(identifier: MobileAccessibilityID.clipCard)
            .matching(NSPredicate(format: "label CONTAINS %@", "Packing list")).firstMatch
        XCTAssertTrue(packing.waitForExistence(timeout: timeout))
        element(MobileAccessibilityID.settingsButton, in: app).tap()
        let hide = app.switches[MobileAccessibilityID.hideContentsToggle].firstMatch
        for _ in 0..<6 where !hide.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(hide.waitForExistence(timeout: timeout))
        hide.tap()
        if hide.value as? String == "0" { hide.switches.firstMatch.tap() }
        XCTAssertEqual(hide.value as? String, "1")
        app.buttons["Done"].firstMatch.tap()

        XCTAssertTrue(element(MobileAccessibilityID.clipCard, in: app).waitForExistence(timeout: timeout))
        XCTAssertFalse(packing.exists, "a covered card says its kind, never its text")
        capture("Cards covered by Hide Clip Contents")
    }
}
