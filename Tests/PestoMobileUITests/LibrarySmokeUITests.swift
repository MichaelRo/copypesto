// SPDX-License-Identifier: MIT
import UIKit
import XCTest

/// One pass through the library per idiom, on a seeded, isolated launch (`-UITestMode`: its own store, preferences
/// and pasteboard): the clips are listed, a search finds one, the clip opens and Copy works.
@MainActor
final class LibrarySmokeUITests: XCTestCase {
    private let timeout: TimeInterval = 15

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["PESTO_UITEST_SESSION"] = "mobile-\(UUID().uuidString)"
        app.launchEnvironment["PESTO_UITEST_SEED"] = "basic"
        app.launch()
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func rows(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: MobileAccessibilityID.clipRow)
    }

    private func waitForSeededClips(in app: XCUIApplication) {
        let deadline = Date.now.addingTimeInterval(timeout)
        while rows(in: app).count < 5, Date.now < deadline {
            _ = rows(in: app).firstMatch.waitForExistence(timeout: 0.5)
        }
        XCTAssertGreaterThanOrEqual(rows(in: app).count, 5, "the seeded clips are listed")
    }

    private func searchResult(in app: XCUIApplication) -> XCUIElement {
        rows(in: app).matching(NSPredicate(format: "label CONTAINS %@", "Packing list")).firstMatch
    }

    /// Another tab can keep its rows in the tree off screen, so "shown" means hittable.
    private func visibleRow(containing text: String, in app: XCUIApplication) -> Bool {
        let matches = rows(in: app).matching(NSPredicate(format: "label CONTAINS %@", text))
        return matches.allElementsBoundByIndex.contains { $0.isHittable }
    }

    private func capture(_ name: String, of app: XCUIApplication) {
        _ = app
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func copyAndCheck(in app: XCUIApplication) {
        let copy = element(MobileAccessibilityID.copyButton, in: app)
        XCTAssertTrue(copy.waitForExistence(timeout: timeout), "the clip offers Copy")
        copy.tap()
        let notice = element(MobileAccessibilityID.noticeBanner, in: app)
        XCTAssertTrue(notice.waitForExistence(timeout: timeout), "copying says so")
    }

    func test_onIPhone_theLibraryListsSearchesOpensAndCopies() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "the iPhone pass")
        let app = launch()
        waitForSeededClips(in: app)
        capture("iphone-library", of: app)

        app.tabBars.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        field.tap()
        field.typeText("Packing")
        let found = searchResult(in: app)
        XCTAssertTrue(found.waitForExistence(timeout: timeout), "the search finds the note")
        XCTAssertFalse(visibleRow(containing: "3F7D4E", in: app), "the search leaves out what does not match")
        capture("iphone-search", of: app)

        found.tap()
        XCTAssertTrue(element(MobileAccessibilityID.clipDetail, in: app).waitForExistence(timeout: timeout))
        copyAndCheck(in: app)
        capture("iphone-detail", of: app)
    }

    func test_onIPad_theSplitViewShowsSidebarListAndDetail() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "the iPad pass")
        // In portrait an iPad keeps a three-column split view's sidebar behind Show Sidebar; landscape shows all three.
        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock { @MainActor in XCUIDevice.shared.orientation = .portrait }
        let app = launch()
        waitForSeededClips(in: app)
        XCTAssertTrue(element(MobileAccessibilityID.sidebar, in: app).waitForExistence(timeout: timeout))
        XCTAssertTrue(element(MobileAccessibilityID.emptyDetail, in: app).exists, "no clip is chosen yet")
        capture("ipad-library", of: app)

        searchResult(in: app).tap()
        XCTAssertTrue(element(MobileAccessibilityID.clipDetail, in: app).waitForExistence(timeout: timeout))
        XCTAssertTrue(element(MobileAccessibilityID.sidebar, in: app).exists, "the sidebar stays beside the detail")
        copyAndCheck(in: app)
        capture("ipad-detail", of: app)

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        field.tap()
        field.typeText("Packing")
        XCTAssertTrue(searchResult(in: app).waitForExistence(timeout: timeout), "the search finds the note")
        XCTAssertFalse(visibleRow(containing: "3F7D4E", in: app), "the search leaves out what does not match")
        capture("ipad-search", of: app)
    }
}
