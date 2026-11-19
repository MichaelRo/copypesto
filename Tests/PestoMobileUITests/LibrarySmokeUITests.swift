// SPDX-License-Identifier: MIT
import UIKit
import XCTest

/// One pass through the library page per idiom, on a seeded, isolated launch (`-UITestMode`: its own store,
/// preferences and pasteboard): the cards are there, a tap copies, a search filters the same grid, the detail opens,
/// and on iPad the sidebar, a collection and the inspector work.
@MainActor
final class LibrarySmokeUITests: MobileUITestCase {
    func test_onIPhone_theLibraryCopiesSearchesAndOpensDetail() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "the iPhone pass")
        let app = launch()
        waitForSeededClips(in: app)
        XCTAssertTrue(element(MobileAccessibilityID.chipRow, in: app).exists, "the chip row sits under the bar")
        XCTAssertTrue(app.buttons["Trip"].waitForExistence(timeout: timeout), "the seeded collection has a chip")
        capture("iphone-library")
        capture("iphone-toolbar-light", app.navigationBars.firstMatch.screenshot())
        let secret = card(containing: "ghp_", in: app)
        if secret.exists { capture("iphone-secret-card", secret.screenshot()) }

        card(containing: "Packing list", in: app).tap()
        XCTAssertTrue(element(MobileAccessibilityID.noticeBanner, in: app).waitForExistence(timeout: timeout))
        capture("iphone-copied")

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        field.tap()
        field.typeText("Packing")
        XCTAssertTrue(card(containing: "Packing list", in: app).waitForExistence(timeout: timeout))
        XCTAssertFalse(visibleCard(containing: "3F7D4E", in: app), "the search leaves out what does not match")
        XCTAssertTrue(app.buttons["Links"].exists, "a search offers the kinds")
        capture("iphone-search")
        app.buttons["close"].firstMatch.tap()

        app.buttons["Pinned"].tap()
        XCTAssertTrue(card(containing: "Gate B7", in: app).waitForExistence(timeout: timeout), "Pinned shows the pin")
        XCTAssertFalse(visibleCard(containing: "Packing list", in: app), "Pinned leaves the rest out")
        openDetail(of: card(containing: "Gate B7", in: app), in: app)
        XCTAssertTrue(element(MobileAccessibilityID.copyButton, in: app).exists, "the detail offers Copy")
        capture("iphone-detail")
    }

    func test_onIPhone_darkAndLargeTextReadAsPesto() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "the iPhone pass")
        let dark = launch(environment: ["PESTO_UITEST_DEFAULT_appearanceMode": "dark"])
        waitForSeededClips(in: dark)
        capture("iphone-library-dark")
        capture("iphone-toolbar-dark", dark.navigationBars.firstMatch.screenshot())
        dark.terminate()

        let large = launch(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        waitForSeededClips(in: large, atLeast: 1)
        let first = cards(in: large).firstMatch
        XCTAssertGreaterThan(first.frame.width, large.windows.firstMatch.frame.width * 0.8, "one card to a row")
        capture("iphone-large-text")
    }

    func test_onIPad_theSidebarCollectionAndInspectorWork() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "the iPad pass")
        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock { @MainActor in XCUIDevice.shared.orientation = .portrait }
        let app = launch()
        waitForSeededClips(in: app)
        let sidebar = element(MobileAccessibilityID.sidebar, in: app)
        XCTAssertTrue(sidebar.waitForExistence(timeout: timeout))
        XCTAssertFalse(element(MobileAccessibilityID.chipRow, in: app).exists, "the sidebar stands in for the chips")
        capture("ipad-library")

        sidebar.staticTexts["Trip"].tap()
        XCTAssertTrue(card(containing: "copypesto.net", in: app).waitForExistence(timeout: timeout))
        XCTAssertFalse(visibleCard(containing: "Packing list", in: app), "the collection shows only its clips")

        openDetail(of: card(containing: "copypesto.net", in: app), in: app)
        XCTAssertTrue(sidebar.exists, "the inspector opens beside the sidebar")
        capture("ipad-inspector")

        app.buttons["Hide Sidebar"].firstMatch.tap()
        XCTAssertTrue(element(MobileAccessibilityID.chipRow, in: app).waitForExistence(timeout: timeout))
        capture("ipad-sidebar-hidden")
    }
}
