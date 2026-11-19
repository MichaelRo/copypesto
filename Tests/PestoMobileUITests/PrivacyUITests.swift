// SPDX-License-Identifier: MIT
import UIKit
import XCTest

/// The iPhone and iPad pass for the History Lock and the content cover (ADR 0054): the lock screen draws no card,
/// and Hide Clip Contents covers every card until one is shown.
@MainActor
final class PrivacyUITests: MobileUITestCase {
    private var idiom: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
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
        capture("\(idiom)-lock-screen")
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
        let packing = card(containing: "Packing list", in: app)
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
        capture("\(idiom)-cards-covered-hide-contents")
    }

    /// Greyed out without the lock, the switch read as a feature the device could not have; it is an exception to the
    /// lock, so it appears only with the lock on.
    func test_whenTheLockIsOff_thenSettingsOffersNoWidgetAndAutoFillException() {
        let app = launch()
        XCTAssertTrue(element(MobileAccessibilityID.clipCard, in: app).waitForExistence(timeout: timeout))
        element(MobileAccessibilityID.settingsButton, in: app).tap()
        let lock = app.switches[MobileAccessibilityID.historyLockToggle].firstMatch
        for _ in 0..<6 where !lock.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(lock.waitForExistence(timeout: timeout))
        XCTAssertEqual(lock.value as? String, "0")
        XCTAssertFalse(app.switches[MobileAccessibilityID.showsClipsOutsideToggle].exists)
    }

    func test_whenTheSceneIsCaptured_thenEveryCardIsCoveredAndOffersShow() {
        let app = launch(environment: [
            "PESTO_UITEST_DEFAULT_screenSharingPrivacy": "true",
            "PESTO_UITEST_DEFAULT_uitestForcesSceneCapture": "true"
        ])
        let allCards = cards(in: app)
        let shows = app.descendants(matching: .any).matching(identifier: MobileAccessibilityID.showUnderCoverButton)
        XCTAssertTrue(allCards.firstMatch.waitForExistence(timeout: timeout))
        XCTAssertTrue(shows.firstMatch.waitForExistence(timeout: timeout), "a covered card offers Show")
        XCTAssertGreaterThan(allCards.count, 1)
        XCTAssertEqual(shows.count, allCards.count, "every card on screen is covered and offers Show")
        let packing = card(containing: "Packing list", in: app)
        XCTAssertFalse(packing.exists, "a covered card says its kind, never its text")
        capture("\(idiom)-cards-covered-scene-capture")

        shows.firstMatch.tap()
        XCTAssertEqual(shows.count, allCards.count - 1, "Show uncovers that one card until the capture ends")
    }
}
