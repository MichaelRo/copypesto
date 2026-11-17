// SPDX-License-Identifier: MIT
import XCTest

final class OnboardingAccessibilityLiveTests: PestoUITestCase {
    func test_whenAccessibilityBecomesTrustedOnStep2_thenPollerAdvancesAutomatically() {
        launch(accessibility: "denied", defaults: [:])
        XCTAssertTrue(onboardingWindow.waitUntilExists(timeout: 10), "onboarding did not appear")

        let continueButton = element(AccessibilityID.onboardingContinueButton)
        XCTAssertTrue(continueButton.waitUntilExists(timeout: 10), "no Continue button on step 1")
        continueButton.click()

        XCTAssertTrue(
            element(AccessibilityID.onboardingAccessibilityStep).waitUntilExists(timeout: 5),
            "did not reach Accessibility step"
        )

        send(.setAccessibilityTrusted)

        let grantedText = onboardingWindow.staticTexts.matching(NSPredicate(
            format: "value CONTAINS 'Accessibility Access is on' OR label CONTAINS 'Accessibility Access is on'"
        )).firstMatch
        XCTAssertTrue(
            grantedText.waitUntilExists(timeout: 6),
            "1.5 s poller did not update Accessibility step after trust was granted"
        )
        let step2Continue = element(AccessibilityID.onboardingContinueButton)
        XCTAssertTrue(step2Continue.waitUntilExists(timeout: 5))
        step2Continue.click()
        XCTAssertTrue(
            element(AccessibilityID.onboardingGetStartedButton).waitUntilExists(timeout: 6),
            "did not reach final onboarding step"
        )
    }
}
