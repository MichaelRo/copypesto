// SPDX-License-Identifier: MIT
import XCTest

final class OnboardingAndStatesTests: PestoUITestCase {
    /// With Accessibility already granted the second step still shows, and its Continue moves on.
    private func continueFromPastingStep() {
        XCTAssertTrue(
            element(AccessibilityID.onboardingAccessibilityStep).waitForExistence(timeout: 5),
            "no second step"
        )
        let next = element(AccessibilityID.onboardingContinueButton)
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.click()
    }

    /// The first step introduces the shortcut and creates the key; Continue moves on to the next step.
    private func continueFromShelfStep() {
        XCTAssertTrue(element(AccessibilityID.onboardingShelfStep).waitForExistence(timeout: 10), "no first step")
        let next = element(AccessibilityID.onboardingContinueButton)
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.click()
    }

    func test_onboarding_movesWithTheArrowKeysAndClosesWithEscape() {
        launch(accessibility: "trusted")
        send(.showOnboarding)
        XCTAssertTrue(onboardingWindow.waitForExistence(timeout: 10))
        XCTAssertTrue(element(AccessibilityID.onboardingShelfStep).waitForExistence(timeout: 10))
        XCTAssertFalse(element(AccessibilityID.onboardingBackButton).exists, "the first page has nothing to go back to")

        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(
            element(AccessibilityID.onboardingAccessibilityStep).waitForExistence(timeout: 10),
            "Right Arrow did not move to the second page"
        )

        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(element(AccessibilityID.onboardingGetStartedButton).waitForExistence(timeout: 5))
        XCTAssertTrue(element(AccessibilityID.onboardingBackButton).exists)

        app.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertTrue(
            element(AccessibilityID.onboardingAccessibilityStep).waitForExistence(timeout: 5),
            "Left Arrow did not go back a page"
        )

        element(AccessibilityID.onboardingBackButton).click()
        XCTAssertTrue(element(AccessibilityID.onboardingShelfStep).waitForExistence(timeout: 5), "Back did not go back")

        app.typeKey(.escape, modifierFlags: [])
        waitForNonExistence(onboardingWindow, timeout: 5, "Escape did not close the welcome screen")
    }

    func test_firstRun_withAccessibilityDenied_showsOnboardingAndTheOverlayBanner() {
        launch(accessibility: "denied", defaults: [:])

        XCTAssertTrue(onboardingWindow.waitForExistence(timeout: 10), "onboarding did not appear")
        app.activate()
        capture("onboarding-shelf-step", of: onboardingWindow)
        continueFromShelfStep()
        XCTAssertTrue(element(AccessibilityID.onboardingAccessibilityStep).waitForExistence(timeout: 5))
        app.activate()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        capture("onboarding-accessibility-denied", of: onboardingWindow)

        showOverlay()
        XCTAssertTrue(
            element(AccessibilityID.accessibilityBanner).waitForExistence(timeout: 5),
            "the overlay should warn that auto-paste needs Accessibility"
        )
        capture("overlay-accessibility-banner")
    }

    func test_onboarding_whenEverythingIsDone_keepsEveryLineInsideTheWindow() {
        launch(accessibility: "trusted")
        send(.showOnboarding)
        XCTAssertTrue(onboardingWindow.waitForExistence(timeout: 10))
        continueFromShelfStep()
        continueFromPastingStep()

        let toggle = element(AccessibilityID.launchAtLoginToggle)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.click()
        let caption = element(AccessibilityID.launchAtLoginUnavailable)
        XCTAssertTrue(
            caption.waitForExistence(timeout: 5),
            "this copy cannot register a login item, so pressing the switch shows why"
        )
        capture("onboarding-all-done", of: onboardingWindow)

        let window = onboardingWindow.frame
        XCTAssertLessThanOrEqual(
            caption.frame.maxY, window.maxY, "the last caption is cut off by the bottom of the onboarding window"
        )
        XCTAssertGreaterThanOrEqual(caption.frame.minY, window.minY)
    }

    /// The welcome screen stays minimal, and a person who wants to decide a little more opens More options.
    func test_onboarding_moreOptions_opensTwoMoreChoices_insideTheWindow() {
        launch(accessibility: "trusted")
        send(.showOnboarding)
        XCTAssertTrue(onboardingWindow.waitForExistence(timeout: 10))
        continueFromShelfStep()
        continueFromPastingStep()
        XCTAssertFalse(element(AccessibilityID.onboardingMenuBarToggle).exists, "the extra choices start folded away")

        let more = element(AccessibilityID.onboardingMoreOptions)
        XCTAssertTrue(more.waitForExistence(timeout: 5), "no More options on the last step")
        more.click()

        let menuBar = element(AccessibilityID.onboardingMenuBarToggle)
        let devices = element(AccessibilityID.onboardingDevicesToggle)
        XCTAssertTrue(menuBar.waitForExistence(timeout: 5), "no menu bar choice under More options")
        XCTAssertTrue(devices.waitForExistence(timeout: 5), "no other-devices choice under More options")
        capture("onboarding-more-options", of: onboardingWindow)
        let window = onboardingWindow.frame
        let lastChoice = element(AccessibilityID.onboardingLockToggle).exists
            ? element(AccessibilityID.onboardingLockToggle)
            : devices
        XCTAssertLessThanOrEqual(lastChoice.frame.maxY, window.maxY, "the last choice is cut off by the window")
        XCTAssertLessThanOrEqual(
            element(AccessibilityID.onboardingGetStartedButton).frame.maxY, window.maxY, "Get Started left the window"
        )
    }

    func test_onboarding_whenEverythingIsDone_runsLaunchAtLoginAcrossTheWidthOfGetStarted() {
        launch(accessibility: "trusted")
        send(.showOnboarding)
        XCTAssertTrue(onboardingWindow.waitForExistence(timeout: 10))
        continueFromShelfStep()
        continueFromPastingStep()

        let toggle = element(AccessibilityID.launchAtLoginToggle)
        let button = element(AccessibilityID.onboardingGetStartedButton)
        let label = onboardingWindow.staticTexts["Launch Pesto at login"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "the preferences appear on the last step")
        XCTAssertTrue(label.exists, "the switch needs its label")
        app.activate()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        capture("onboarding-ready", of: onboardingWindow)

        // The row sits in a card as wide as the button, with a 16 pt inset.
        XCTAssertEqual(
            label.frame.minX,
            button.frame.minX + 16,
            accuracy: 4,
            "the label is not at the card's left edge"
        )
        XCTAssertEqual(
            toggle.frame.maxX,
            button.frame.maxX - 16,
            accuracy: 4,
            "the switch is not at the card's right edge"
        )
    }

    func test_onboarding_canBeFinishedWithoutAccessibility_andStaysOpenUntilGetStarted() {
        launch(accessibility: "denied", defaults: [:])
        XCTAssertTrue(onboardingWindow.waitForExistence(timeout: 10))
        app.activate()
        continueFromShelfStep()

        element(AccessibilityID.onboardingSkipAccessibilityButton).click()
        let getStarted = element(AccessibilityID.onboardingGetStartedButton)
        XCTAssertTrue(getStarted.waitForExistence(timeout: 5), "skipping Accessibility should allow finishing")
        app.activate()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        capture("onboarding-skipped-accessibility", of: onboardingWindow)

        RunLoop.current.run(until: Date().addingTimeInterval(3))
        XCTAssertTrue(onboardingWindow.exists, "the window must not close by itself")

        getStarted.click()
        waitForNonExistence(onboardingWindow, timeout: 5, "Get Started should close onboarding")
    }

    func test_closingOnboarding_keepsTheAppRunning() {
        // Same over-release as the Settings window: the delegate owns the window and AppKit also released it.
        launch(accessibility: "denied", defaults: [:])
        XCTAssertTrue(onboardingWindow.waitForExistence(timeout: 10))

        onboardingWindow.buttons[XCUIIdentifierCloseWindow].click()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))

        XCTAssertNotEqual(app.state, .notRunning, "closing onboarding terminated the app")
    }

    func test_onboardedUser_withAccessibilityGranted_seesNoOnboardingOrBanner() {
        launch()

        showOverlay()

        XCTAssertFalse(onboardingWindow.exists)
        XCTAssertFalse(element(AccessibilityID.accessibilityBanner).exists)
    }

    func test_emptyHistory_opensWithoutCards() {
        launch(seed: "empty")

        showOverlay(expectingCards: false)

        XCTAssertEqual(cards.count, 0)
        XCTAssertTrue(
            element(AccessibilityID.shelfEmptyState).waitForExistence(timeout: 5),
            "empty shelf shows no explanation"
        )
        capture("overlay-empty")
    }

    func test_largeHistory_opensAndScrolls() {
        launch(seed: "large", timeout: 300)

        let start = Date()
        showOverlay()
        let opened = Date().timeIntervalSince(start)
        overlay.swipeLeft()
        overlay.swipeLeft()

        XCTAssertGreaterThan(cards.count, 0, "grid went blank after scrolling a 5,000-item history")
        XCTAssertLessThan(opened, 8, "overlay took \(opened) s to show with 5,000 items")
        capture("overlay-large-history")
    }

    func test_appearance_lightAndDark() {
        for mode in ["light", "dark"] {
            launch(defaults: ["hasOnboarded": "true", "appearanceMode": mode])
            showOverlay()
            RunLoop.current.run(until: Date().addingTimeInterval(1))
            capture("overlay-\(mode)")
            app.terminate()
            try? FileManager.default.removeItem(at: workDirectory.appendingPathComponent(UITestSupport.readyFileName))
        }
    }
}
