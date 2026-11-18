// SPDX-License-Identifier: MIT
import UIKit
import XCTest

/// One pass through the library page per idiom, on a seeded, isolated launch (`-UITestMode`: its own store,
/// preferences and pasteboard): the cards are there, a tap copies, a search filters the same grid, the detail opens,
/// and on iPad the sidebar, a collection and the inspector work.
@MainActor
final class LibrarySmokeUITests: XCTestCase {
    private let timeout: TimeInterval = 15

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
    }

    private func launch(environment: [String: String] = [:], arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + arguments
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

    private func cards(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: MobileAccessibilityID.clipCard)
    }

    private func card(containing text: String, in app: XCUIApplication) -> XCUIElement {
        cards(in: app).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func waitForSeededClips(in app: XCUIApplication, atLeast count: Int = 4) {
        let deadline = Date.now.addingTimeInterval(timeout)
        while cards(in: app).count < count, Date.now < deadline {
            _ = cards(in: app).firstMatch.waitForExistence(timeout: 0.5)
        }
        XCTAssertGreaterThanOrEqual(cards(in: app).count, count, "the seeded clips are on cards")
    }

    private func visibleCard(containing text: String, in app: XCUIApplication) -> Bool {
        let matches = cards(in: app).matching(NSPredicate(format: "label CONTAINS %@", text))
        return matches.allElementsBoundByIndex.contains { $0.isHittable }
    }

    private func capture(_ name: String, _ screenshot: XCUIScreenshot = XCUIScreen.main.screenshot()) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openDetail(of target: XCUIElement, in app: XCUIApplication) {
        target.press(forDuration: 1.0)
        let edit = app.buttons["Edit Details"]
        XCTAssertTrue(edit.waitForExistence(timeout: timeout), "the long-press menu offers Edit Details")
        edit.tap()
        XCTAssertTrue(element(MobileAccessibilityID.clipDetail, in: app).waitForExistence(timeout: timeout))
    }

    func test_onIPhone_theLibraryCopiesSearchesAndOpensDetail() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "the iPhone pass")
        let app = launch()
        waitForSeededClips(in: app)
        XCTAssertTrue(element(MobileAccessibilityID.chipRow, in: app).exists, "the chip row sits under the bar")
        XCTAssertTrue(app.buttons["Trip"].waitForExistence(timeout: timeout), "the seeded collection has a chip")
        capture("iphone-library")
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
