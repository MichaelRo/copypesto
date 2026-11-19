// SPDX-License-Identifier: MIT
import UIKit
import XCTest

/// Shared iOS UI-test harness with isolated session seeding and context-menu quiescence handling.
/// UIKit's `_UIContextMenuPresentation` keeps a `UIViewPropertyAnimator` live while a card menu is open, which causes
/// XCUITest's animation-idle wait to stall for 60 seconds on long-presses and menu taps unless
/// `idleAnimationWaitEnabled` is temporarily suspended for those context-menu interactions.
@MainActor
class MobileUITestCase: XCTestCase {
    let timeout: TimeInterval = 15
    let session = "mobile-\(UUID().uuidString)"

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
    }

    func launch(
        environment: [String: String] = [:], arguments: [String] = [], seed: String = "basic"
    )
    -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + arguments
        app.launchEnvironment["PESTO_UITEST_SESSION"] = session
        app.launchEnvironment["PESTO_UITEST_SEED"] = seed
        for (key, value) in environment {
            app.launchEnvironment[key] = value
        }
        app.launch()
        return app
    }

    func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func cards(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: MobileAccessibilityID.clipCard)
    }

    func card(containing text: String, in app: XCUIApplication) -> XCUIElement {
        cards(in: app).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func visibleCard(containing text: String, in app: XCUIApplication) -> Bool {
        cards(in: app).matching(NSPredicate(format: "label CONTAINS %@", text))
            .allElementsBoundByIndex.contains { $0.isHittable }
    }

    func waitForSeededClips(
        in app: XCUIApplication, atLeast count: Int = 4, file: StaticString = #filePath, line: UInt = #line
    ) {
        let deadline = Date.now.addingTimeInterval(timeout)
        while cards(in: app).count < count, Date.now < deadline {
            _ = cards(in: app).firstMatch.waitForExistence(timeout: 0.5)
        }
        XCTAssertGreaterThanOrEqual(
            cards(in: app).count, count, "the seeded clips are on cards", file: file, line: line
        )
    }

    func capture(_ name: String, _ screenshot: XCUIScreenshot = XCUIScreen.main.screenshot()) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func withoutIdleAnimationWait(in app: XCUIApplication, perform work: () -> Void) {
        let key = "idleAnimationWaitEnabled"
        let setter = NSSelectorFromString("setIdleAnimationWaitEnabled:")
        let previous = app.responds(to: setter) ? (app.value(forKey: key) as? Bool) : nil
        if previous != nil { app.setValue(false, forKey: key) }
        defer {
            if let previous { app.setValue(previous, forKey: key) }
        }
        work()
    }

    func pressForContextMenu(
        _ target: XCUIElement, in app: XCUIApplication, duration: TimeInterval = 1.0
    ) {
        withoutIdleAnimationWait(in: app) {
            target.press(forDuration: duration)
        }
    }

    func chooseContextMenuItem(
        _ titles: String..., on target: XCUIElement, in app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        withoutIdleAnimationWait(in: app) {
            target.press(forDuration: 1.0)
            for title in titles {
                let item = app.buttons[title]
                XCTAssertTrue(
                    item.waitForExistence(timeout: timeout),
                    "expected context menu item '\(title)'", file: file, line: line
                )
                item.tap()
            }
        }
    }

    func openDetail(
        of target: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        chooseContextMenuItem("Edit Details", on: target, in: app, file: file, line: line)
        XCTAssertTrue(
            element(MobileAccessibilityID.clipDetail, in: app).waitForExistence(timeout: timeout),
            "expected clip detail to open", file: file, line: line
        )
    }
}
