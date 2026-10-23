// SPDX-License-Identifier: MIT
import XCTest

/// The one-time offer on the shelf to bring a history over from an installed clipboard manager. A UI-test launch finds
/// the
/// app its import fixture names (`PESTO_UITEST_IMPORT_FIXTURE`); a launch without one finds none.
final class ImportOfferUITests: PestoUITestCase {
    func test_withMaccyInstalled_theShelfOffersToImport_andNotNowEndsTheOfferForGood() {
        launch(importFixture: "maccy")
        showOverlay()

        let banner = element(AccessibilityID.importOfferBanner)
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "no import offer on the shelf")
        XCTAssertTrue(element(AccessibilityID.importOfferImportButton).exists)
        capture("import-offer-banner")

        element(AccessibilityID.importOfferDismissButton).click()
        waitForNonExistence(banner, timeout: 5, "Not now left the offer on the shelf")

        relaunch()
        showOverlay()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertFalse(element(AccessibilityID.importOfferBanner).exists, "the offer came back after Not now")
    }

    func test_accepting_opensSettingsAtData_andShowsThatAppsPreview() {
        launch(importFixture: "maccy")
        showOverlay()
        XCTAssertTrue(element(AccessibilityID.importOfferBanner).waitForExistence(timeout: 10))

        element(AccessibilityID.importOfferImportButton).click()

        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10), "Settings did not open")
        XCTAssertTrue(
            element(AccessibilityID.importPreviewSheet).waitForExistence(timeout: 10),
            "the import for the offered app did not start with its preview"
        )
        element(AccessibilityID.importPreviewCancel).click()
    }

    func test_withTwoAppsInstalled_theBannerChoosesAndTheCardListsEachApp() {
        launch(importFixture: "paste,maccy")
        showOverlay()
        XCTAssertTrue(element(AccessibilityID.importOfferBanner).waitForExistence(timeout: 10))

        element(AccessibilityID.importOfferImportButton).click()

        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10), "Settings did not open")
        for app in ["paste", "maccy"]
            where !element(AccessibilityID.foundOnThisMacRow(app)).waitForExistence(timeout: 10)
        {
            dumpState("found-card-missing-\(app)")
            XCTFail("no Found on this Mac row for \(app)")
        }
        XCTAssertFalse(
            element(AccessibilityID.importPreviewSheet).exists,
            "choosing started an import by itself: each import keeps its own consent"
        )
        capture("found-on-this-mac")
    }

    func test_withNoClipboardManagerInstalled_thereIsNoOffer() {
        launch()
        showOverlay()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))

        XCTAssertFalse(element(AccessibilityID.importOfferBanner).exists, "an offer with nothing to import from")
    }
}
