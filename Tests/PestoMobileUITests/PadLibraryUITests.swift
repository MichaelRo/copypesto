// SPDX-License-Identifier: MIT
import UIKit
import XCTest

/// What only the iPad has, on a seeded, isolated launch: the hardware keyboard's commands, a card's menu reaching the
/// sidebar, and the grid in both orientations.
@MainActor
final class PadLibraryUITests: XCTestCase {
    private let timeout: TimeInterval = 15

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "the iPad pass")
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

    private func cards(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: MobileAccessibilityID.clipCard)
    }

    private func card(containing text: String, in app: XCUIApplication) -> XCUIElement {
        cards(in: app).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func visibleCard(containing text: String, in app: XCUIApplication) -> Bool {
        cards(in: app).matching(NSPredicate(format: "label CONTAINS %@", text))
            .allElementsBoundByIndex.contains { $0.isHittable }
    }

    private func waitForSeededClips(in app: XCUIApplication) {
        XCTAssertTrue(card(containing: "Packing list", in: app).waitForExistence(timeout: timeout), "seeded")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// XCUITest sends a key only to an element with text focus, and a card never has it, so ⌘F from the grid is a hand
    /// check; from the search field, ⌘N and ⌘S reach the app's commands.
    func test_onIPad_withTheKeyboardCommandNWritesANoteThatCommandSSaves() {
        let app = launch()
        waitForSeededClips(in: app)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        field.tap()
        app.typeText("keyboard")
        XCTAssertTrue(
            card(containing: "Packing list", in: app).waitForNonExistence(timeout: timeout),
            "the search filters the grid"
        )

        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.navigationBars["New Note"].waitForExistence(timeout: timeout), "⌘N opens the composer")
        app.typeText("Written with the keyboard")
        app.typeKey("s", modifierFlags: .command)
        XCTAssertFalse(app.navigationBars["New Note"].waitForExistence(timeout: 2), "⌘S saves and closes")
        XCTAssertTrue(
            card(containing: "Written with the keyboard", in: app).waitForExistence(timeout: timeout),
            "the saved note joins the search it matches"
        )
        capture("ipad-keyboard-note")
    }

    func test_onIPad_aCardsMenuPinsItAndTheSidebarsPinnedShowsIt() {
        let app = launch()
        waitForSeededClips(in: app)
        let sidebar = element(MobileAccessibilityID.sidebar, in: app)
        if !sidebar.exists { app.buttons["Show Sidebar"].firstMatch.tap() }
        XCTAssertTrue(sidebar.waitForExistence(timeout: timeout))

        card(containing: "Packing list", in: app).press(forDuration: 1.0)
        let pin = app.buttons["Pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: timeout), "the card's menu offers Pin")
        pin.tap()

        sidebar.staticTexts["Pinned"].tap()
        XCTAssertTrue(card(containing: "Packing list", in: app).waitForExistence(timeout: timeout))
        XCTAssertTrue(card(containing: "Gate B7", in: app).exists, "the seeded pin stays")
        capture("ipad-pinned")
    }

    func test_onIPad_theGridFillsBothOrientationsWithMoreThanOneColumn() {
        addTeardownBlock { @MainActor in XCUIDevice.shared.orientation = .portrait }
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let app = launch()
            waitForSeededClips(in: app)
            let grid = element(MobileAccessibilityID.clipGrid, in: app)
            XCTAssertTrue(grid.waitForExistence(timeout: timeout))
            let first = cards(in: app).firstMatch
            XCTAssertLessThan(first.frame.width, grid.frame.width / 2, "more than one column in \(orientation)")
            capture("ipad-grid-\(orientation == .portrait ? "portrait" : "landscape")")
            app.terminate()
        }
    }
}
