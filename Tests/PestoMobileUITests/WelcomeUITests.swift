// SPDX-License-Identifier: MIT
import UIKit
import XCTest

/// The first-run welcome (ADR 0057) on a seeded, isolated launch that asks for it, and the one-time AutoFill tip.
/// Every step attaches a screenshot, in light and dark and at a large accessibility text size.
@MainActor
final class WelcomeUITests: MobileUITestCase {
    private var idiom: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
    }

    private func launchWelcome(
        environment: [String: String] = [:], arguments: [String] = [], asksForWelcome: Bool = true
    )
    -> XCUIApplication {
        var merged = asksForWelcome ? ["PESTO_UITEST_DEFAULT_uitestShowsWelcome": "true"] : [:]
        for (key, value) in environment {
            merged[key] = value
        }
        return launch(environment: merged, arguments: arguments, seed: "basic")
    }

    func captureWelcome(_ name: String) {
        capture("\(idiom)-\(name)")
    }

    private func tap(_ identifier: String, in app: XCUIApplication) {
        let button = element(identifier, in: app)
        XCTAssertTrue(button.waitForExistence(timeout: timeout), identifier)
        button.tap()
    }

    private func waitForLibrary(in app: XCUIApplication) {
        XCTAssertTrue(
            element(MobileAccessibilityID.clipCard, in: app).waitForExistence(timeout: timeout),
            "the library is under the welcome"
        )
    }

    private func linkPreviewsValue(in app: XCUIApplication) -> String? {
        tap(MobileAccessibilityID.settingsButton, in: app)
        let toggle = app.switches[MobileAccessibilityID.linkPreviewsToggle].firstMatch
        for _ in 0..<8 where !toggle.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: timeout))
        return toggle.value as? String
    }

    private func walkThrough(_ label: String, in app: XCUIApplication) {
        XCTAssertTrue(element(MobileAccessibilityID.welcomeKeepStep, in: app).waitForExistence(timeout: timeout))
        XCTAssertTrue(app.staticTexts["Step 1 of 3. Keep what you copy"].exists, "the title says which step this is")
        XCTAssertFalse(app.staticTexts["Step 2 of 3. Two choices"].exists, "VoiceOver reaches only the step in view")
        sleep(2)
        captureWelcome("\(label)-step1-keep")
        tap(MobileAccessibilityID.welcomeContinue, in: app)
        XCTAssertTrue(element(MobileAccessibilityID.welcomeChoicesStep, in: app).waitForExistence(timeout: timeout))
        sleep(1)
        captureWelcome("\(label)-step2-choices")
        tap(MobileAccessibilityID.welcomeContinue, in: app)
        XCTAssertTrue(element(MobileAccessibilityID.welcomeSyncStep, in: app).waitForExistence(timeout: timeout))
        sleep(2)
        captureWelcome("\(label)-step3-sync")
    }

    func test_whenFirstLaunch_thenThreeStepsLeadToTheLibraryAndAreNotShownAgain() {
        let app = launchWelcome()
        XCTAssertTrue(element(MobileAccessibilityID.welcomeKeepStep, in: app).waitForExistence(timeout: timeout))
        XCTAssertTrue(element(MobileAccessibilityID.welcomeSkip, in: app).exists, "Skip is on the first step")
        tap(MobileAccessibilityID.welcomeContinue, in: app)

        XCTAssertTrue(element(MobileAccessibilityID.welcomeChoicesStep, in: app).waitForExistence(timeout: timeout))
        let previews = app.switches[MobileAccessibilityID.welcomeLinkPreviews].firstMatch
        XCTAssertTrue(previews.waitForExistence(timeout: timeout))
        XCTAssertEqual(previews.value as? String, "1", "link previews are on, in view, when step two appears")
        let lock = app.switches[MobileAccessibilityID.welcomeLock].firstMatch
        XCTAssertEqual(lock.value as? String, "0", "the lock is offered off")
        XCTAssertTrue(element(MobileAccessibilityID.welcomeSkip, in: app).exists, "Skip is on every step")
        tap(MobileAccessibilityID.welcomeContinue, in: app)

        XCTAssertTrue(element(MobileAccessibilityID.welcomeSyncStep, in: app).waitForExistence(timeout: timeout))
        XCTAssertTrue(element(MobileAccessibilityID.welcomeTurnOnSync, in: app).exists)
        XCTAssertTrue(element(MobileAccessibilityID.welcomeSkip, in: app).exists, "Skip is on every step")
        tap(MobileAccessibilityID.welcomeNotNow, in: app)
        waitForLibrary(in: app)
        XCTAssertFalse(element(MobileAccessibilityID.welcomeSyncStep, in: app).exists)
        XCTAssertEqual(linkPreviewsValue(in: app), "1", "Settings shows the choice the welcome made")
        app.terminate()

        let second = launchWelcome()
        waitForLibrary(in: second)
        XCTAssertFalse(
            element(MobileAccessibilityID.welcomeKeepStep, in: second).exists,
            "a second launch has no welcome"
        )
    }

    func test_whenSkippedOnTheFirstStep_thenTheLibraryShowsAndLinkPreviewsStayOff() {
        let app = launchWelcome()
        XCTAssertTrue(element(MobileAccessibilityID.welcomeKeepStep, in: app).waitForExistence(timeout: timeout))
        tap(MobileAccessibilityID.welcomeSkip, in: app)

        waitForLibrary(in: app)
        XCTAssertFalse(element(MobileAccessibilityID.welcomeKeepStep, in: app).exists)
        XCTAssertEqual(linkPreviewsValue(in: app), "0", "a welcome skipped on step one switches nothing on")
    }

    func test_whenShowWelcomeAgainIsChosen_thenItOpensAgainWithTheStoredChoice() {
        let app = launchWelcome()
        XCTAssertTrue(element(MobileAccessibilityID.welcomeKeepStep, in: app).waitForExistence(timeout: timeout))
        tap(MobileAccessibilityID.welcomeSkip, in: app)
        waitForLibrary(in: app)

        tap(MobileAccessibilityID.settingsButton, in: app)
        let again = app.buttons[MobileAccessibilityID.showWelcomeAgain].firstMatch
        for _ in 0..<10 where !again.isHittable {
            app.swipeUp()
        }
        again.tap()

        XCTAssertTrue(element(MobileAccessibilityID.welcomeKeepStep, in: app).waitForExistence(timeout: timeout))
        tap(MobileAccessibilityID.welcomeContinue, in: app)
        let previews = app.switches[MobileAccessibilityID.welcomeLinkPreviews].firstMatch
        XCTAssertTrue(previews.waitForExistence(timeout: timeout))
        XCTAssertEqual(
            previews.value as? String,
            "1",
            "the first welcome never switched it on, so it does now: nothing was stored"
        )
    }

    func test_whenEachStepIsShown_thenAScreenshotIsAttachedInLightAndDark() {
        let light = launchWelcome(environment: ["PESTO_UITEST_DEFAULT_appearanceMode": "light"])
        walkThrough("light", in: light)
        light.terminate()

        let dark = launchWelcome(
            environment: ["PESTO_UITEST_DEFAULT_appearanceMode": "dark", "PESTO_UITEST_DEFAULT_welcomeShown": "false"]
        )
        walkThrough("dark", in: dark)
    }

    func test_whenTextIsVeryLarge_thenEachStepStillShowsItsButtons() {
        let app = launchWelcome(
            arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        )
        walkThrough("large-text", in: app)
        XCTAssertTrue(element(MobileAccessibilityID.welcomeTurnOnSync, in: app).isHittable, "buttons stay pinned")
        XCTAssertTrue(element(MobileAccessibilityID.welcomeNotNow, in: app).isHittable, "buttons stay pinned")
        XCTAssertFalse(
            element(MobileAccessibilityID.welcomeSkip, in: app).exists,
            "at accessibility sizes the last step drops Skip, since Not Now does the same"
        )
        tap(MobileAccessibilityID.welcomeNotNow, in: app)
        waitForLibrary(in: app)
    }

    func test_whenOnALaterStep_thenBackReturnsOneStepWithoutADrag() {
        let app = launchWelcome()
        XCTAssertTrue(element(MobileAccessibilityID.welcomeKeepStep, in: app).waitForExistence(timeout: timeout))
        XCTAssertFalse(element(MobileAccessibilityID.welcomeBack, in: app).exists, "no Back on the first step")
        tap(MobileAccessibilityID.welcomeContinue, in: app)
        XCTAssertTrue(app.staticTexts["Step 2 of 3. Two choices"].waitForExistence(timeout: timeout))
        tap(MobileAccessibilityID.welcomeContinue, in: app)
        XCTAssertTrue(element(MobileAccessibilityID.welcomeSyncStep, in: app).waitForExistence(timeout: timeout))

        tap(MobileAccessibilityID.welcomeBack, in: app)
        XCTAssertTrue(app.staticTexts["Step 2 of 3. Two choices"].waitForExistence(timeout: timeout))
        tap(MobileAccessibilityID.welcomeBack, in: app)
        XCTAssertTrue(app.staticTexts["Step 1 of 3. Keep what you copy"].waitForExistence(timeout: timeout))
        XCTAssertFalse(element(MobileAccessibilityID.welcomeBack, in: app).exists)
    }

    func test_onIPad_whenTheSheetIsSwipedDown_thenItCountsAsSkip() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "the iPad pass")
        let app = launchWelcome()
        let step = element(MobileAccessibilityID.welcomeKeepStep, in: app)
        XCTAssertTrue(step.waitForExistence(timeout: timeout))
        XCTAssertLessThan(step.frame.width, app.windows.firstMatch.frame.width * 0.9, "a form sheet, not full screen")
        let privacyLine = "iPad keeps your clipboard private, so Pesto adds a copy only when you ask."
        XCTAssertTrue(app.staticTexts[privacyLine].exists, "the welcome names the device it runs on")
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: 0, dy: -step.frame.height / 2 + 8))
        top.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.0)))

        waitForLibrary(in: app)
        XCTAssertFalse(element(MobileAccessibilityID.welcomeKeepStep, in: app).waitForExistence(timeout: 2))
        XCTAssertEqual(linkPreviewsValue(in: app), "0", "swiping down is Skip: nothing was switched on")
    }

    func test_whenTheFirstClipIsPinned_thenTheAutoFillTipAppearsOnceAndCanBeDismissed() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "the iPhone pass")
        let app = launchWelcome(
            environment: ["PESTO_UITEST_DEFAULT_uitestShowsAutoFillTip": "true"], asksForWelcome: false
        )
        let packing = card(containing: "Packing list", in: app)
        XCTAssertTrue(packing.waitForExistence(timeout: timeout))
        XCTAssertFalse(element(MobileAccessibilityID.autoFillTip, in: app).exists, "not before a clip is kept")
        chooseContextMenuItem("Pin", on: packing, in: app)

        XCTAssertTrue(element(MobileAccessibilityID.autoFillTip, in: app).waitForExistence(timeout: timeout))
        XCTAssertTrue(element(MobileAccessibilityID.autoFillTipTurnOn, in: app).exists)
        captureWelcome("autofill-tip")
        tap(MobileAccessibilityID.autoFillTipDismiss, in: app)
        XCTAssertFalse(element(MobileAccessibilityID.autoFillTip, in: app).waitForExistence(timeout: 2))
    }
}
