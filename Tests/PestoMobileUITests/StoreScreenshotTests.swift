// SPDX-License-Identifier: MIT
import UIKit
import XCTest

/// The App Store pictures (`docs/app-store-ios.md`, `docs/pictures.md`): light, seeded, one test per device kind.
/// `make pictures` runs this suite on an iPhone Pro Max and an iPad Pro 13-inch and exports the attachments.
@MainActor
final class StoreScreenshotTests: XCTestCase {
    private let timeout: TimeInterval = 20

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
    }

    private func launch(environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["PESTO_UITEST_SESSION"] = "mobile-\(UUID().uuidString)"
        app.launchEnvironment["PESTO_UITEST_SEED"] = "basic"
        app.launchEnvironment["PESTO_UITEST_DEFAULT_appearanceMode"] = "light"
        app.launchEnvironment["PESTO_UITEST_PICTURE_TEXT"] = "1"
        app.launchEnvironment["PESTO_UITEST_READ_PICTURES"] = "1"
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

    private func waitForLibrary(in app: XCUIApplication) {
        let deadline = Date.now.addingTimeInterval(timeout)
        while cards(in: app).count < 5, Date.now < deadline {
            _ = cards(in: app).firstMatch.waitForExistence(timeout: 0.5)
        }
        XCTAssertGreaterThanOrEqual(cards(in: app).count, 5, "the seeded clips are on cards")
        sleep(2)
    }

    /// The screen's own pixels are in the device's portrait orientation, so a landscape iPad is turned upright.
    private func uprightScreenshot() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let source = XCUIScreen.main.screenshot().image
        let flat = UIGraphicsImageRenderer(size: CGSize(
            width: source.size.width * source.scale, height: source.size.height * source.scale
        ), format: format).image { _ in
            source.draw(in: CGRect(
                x: 0, y: 0, width: source.size.width * source.scale, height: source.size.height * source.scale
            ))
        }
        let turn: CGFloat
        switch XCUIDevice.shared.orientation {
        case .landscapeLeft where flat.size.width < flat.size.height: turn = -.pi / 2
        case .landscapeRight where flat.size.width < flat.size.height: turn = .pi / 2
        default: return flat
        }
        let size = CGSize(width: flat.size.height, height: flat.size.width)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            context.cgContext.rotate(by: turn)
            flat.draw(in: CGRect(
                x: -flat.size.width / 2, y: -flat.size.height / 2, width: flat.size.width, height: flat.size.height
            ))
        }
    }

    private func store(_ name: String) {
        let attachment = XCTAttachment(image: uprightScreenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openDetail(of target: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(target.waitForExistence(timeout: timeout))
        target.press(forDuration: 1.0)
        let edit = app.buttons["Edit Details"]
        XCTAssertTrue(edit.waitForExistence(timeout: timeout), "the long-press menu offers Edit Details")
        edit.tap()
        XCTAssertTrue(element(MobileAccessibilityID.clipDetail, in: app).waitForExistence(timeout: timeout))
    }

    func test_onIPhone_storePictures() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "the iPhone pictures")
        let app = launch()
        waitForLibrary(in: app)
        store("ios-store-iphone-01-library")

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        field.tap()
        field.typeText("boarding")
        XCTAssertTrue(
            cards(in: app).firstMatch.waitForExistence(timeout: timeout),
            "a picture's printed words are found"
        )
        XCTAssertTrue(
            card(containing: "Packing list", in: app).waitForNonExistence(timeout: timeout),
            "the search narrows the grid"
        )
        let searchKey = app.keyboards.buttons["Search"]
        if searchKey.exists { searchKey.tap() }
        sleep(2)
        store("ios-store-iphone-02-search-in-pictures")
        app.buttons["close"].firstMatch.tap()

        openDetail(of: card(containing: "Packing list", in: app), in: app)
        XCTAssertTrue(element(MobileAccessibilityID.editTextButton, in: app).waitForExistence(timeout: timeout))
        sleep(1)
        store("ios-store-iphone-03-detail-edit-text")
        app.buttons["Done"].firstMatch.tap()
    }

    func test_onIPhone_storePictureOfTheWelcomeSync() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "the iPhone pictures")
        let app = launch(environment: ["PESTO_UITEST_DEFAULT_uitestShowsWelcome": "true"])
        for identifier in [MobileAccessibilityID.welcomeKeepStep, MobileAccessibilityID.welcomeChoicesStep] {
            XCTAssertTrue(element(identifier, in: app).waitForExistence(timeout: timeout))
            element(MobileAccessibilityID.welcomeContinue, in: app).tap()
        }
        XCTAssertTrue(element(MobileAccessibilityID.welcomeSyncStep, in: app).waitForExistence(timeout: timeout))
        sleep(2)
        store("ios-store-iphone-04-welcome-sync")
    }

    func test_onIPad_storePictures() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "the iPad pictures")
        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock { @MainActor in XCUIDevice.shared.orientation = .portrait }
        let app = launch()
        waitForLibrary(in: app)
        let sidebar = element(MobileAccessibilityID.sidebar, in: app)
        XCTAssertTrue(sidebar.waitForExistence(timeout: timeout))
        let trip = sidebar.staticTexts["Trip"]
        XCTAssertTrue(trip.waitForExistence(timeout: timeout), "the collection is in the sidebar")
        sleep(2)
        store("ios-store-ipad-01-library")

        trip.tap()
        XCTAssertTrue(card(containing: "copypesto.net", in: app).waitForExistence(timeout: timeout))
        sleep(2)
        store("ios-store-ipad-02-collection")

        openDetail(of: card(containing: "copypesto.net", in: app), in: app)
        sleep(2)
        store("ios-store-ipad-03-inspector")

        app.buttons["New Collection"].firstMatch.tap()
        let name = element(MobileAccessibilityID.collectionNameField, in: app)
        XCTAssertTrue(name.waitForExistence(timeout: timeout))
        name.typeText("Web links")
        app.buttons["Smart"].firstMatch.tap()
        let value = element(MobileAccessibilityID.smartRuleValue, in: app)
        XCTAssertTrue(value.waitForExistence(timeout: timeout), "a smart collection asks for a rule")
        value.tap()
        app.buttons["Link"].firstMatch.tap()
        let hideKeyboard = app.keyboards.buttons["Hide keyboard"]
        if hideKeyboard.exists { hideKeyboard.tap() }
        sleep(1)
        store("ios-store-ipad-04-smart-collection-rules")
    }
}
