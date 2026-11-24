// SPDX-License-Identifier: MIT
import UIKit
import XCTest

/// Captures the iPhone and iPad frames for the website showcase video (light and dark),
/// exported by `scripts/teaser-mobile.sh` into `copypesto-website/video/teaser/public/frames/mobile/`.
@MainActor
final class TeaserMobileFramesTests: XCTestCase {
    private let timeout: TimeInterval = 20

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
    }

    private var appearanceMode: String {
        ProcessInfo.processInfo.environment["PESTO_TEASER_MODE"] == "dark" ? "dark" : "light"
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["PESTO_UITEST_SESSION"] = "teaser-mobile-\(UUID().uuidString)"
        app.launchEnvironment["PESTO_UITEST_SEED"] = "basic"
        app.launchEnvironment["PESTO_UITEST_DEFAULT_appearanceMode"] = appearanceMode
        app.launchEnvironment["PESTO_UITEST_PICTURE_TEXT"] = "1"
        app.launchEnvironment["PESTO_UITEST_READ_PICTURES"] = "1"
        app.launchEnvironment["PESTO_UITEST_REAL_QUICKINSERT"] = "1"
        app.launchEnvironment["PESTO_UITEST_DEFAULT_keyboardEnabled"] = "1"
        app.launch()
        return app
    }

    private func cards(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: MobileAccessibilityID.clipCard)
    }

    private func waitForLibrary(in app: XCUIApplication) {
        let deadline = Date.now.addingTimeInterval(timeout)
        while cards(in: app).count < 5, Date.now < deadline {
            _ = cards(in: app).firstMatch.waitForExistence(timeout: 0.5)
        }
        XCTAssertGreaterThanOrEqual(cards(in: app).count, 5, "the seeded clips are on cards")
        sleep(2)
    }

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

    func test_onIPhone_teaserFrames() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "iPhone teaser frames")
        let app = launch()
        waitForLibrary(in: app)
        store("mobile-iphone-library")

        let messages = XCUIApplication(bundleIdentifier: "com.apple.MobileSMS")
        messages.launch()
        for label in ["Continue", "Not Now", "OK"] where messages.buttons[label].waitForExistence(timeout: 2) {
            messages.buttons[label].tap()
        }
        let compose = messages.buttons["Compose"].firstMatch
        if compose.waitForExistence(timeout: 4) {
            compose.tap()
        } else if messages.cells.firstMatch.waitForExistence(timeout: 3) {
            messages.cells.firstMatch.tap()
        }
        let body = messages.textViews.firstMatch.exists ? messages.textViews.firstMatch : messages.textFields.firstMatch
        if body.waitForExistence(timeout: 4) {
            body.tap()
        } else {
            messages.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        }
        let nextKeyboard = messages.buttons["Next Keyboard"].firstMatch
        if nextKeyboard.waitForExistence(timeout: 4) {
            nextKeyboard.tap()
            sleep(2)
        }
        store("mobile-iphone-search")
    }

    func test_onIPad_teaserFrames() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad teaser frames")
        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock { @MainActor in XCUIDevice.shared.orientation = .portrait }
        let app = launch()
        waitForLibrary(in: app)
        let sidebar = app.descendants(matching: .any).matching(identifier: MobileAccessibilityID.sidebar).firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: timeout))
        sleep(2)
        store("mobile-ipad-library")
        let trip = sidebar.staticTexts["Trip"].firstMatch
        if trip.waitForExistence(timeout: 4) {
            trip.tap()
            sleep(2)
            store("mobile-ipad-collection")
        }
    }
}
