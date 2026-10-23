// SPDX-License-Identifier: MIT
import XCTest

/// The Touch ID lock never engaged at its default (an unregistered timeout preference read as 0, and
/// 0 meant unlocked), unlocked itself when nothing could authenticate, and the quick menu bypassed it.
final class HistoryLockTests: PestoUITestCase {
    private let locked = ["hasOnboarded": "true", "biometricLockEnabled": "true"]

    func test_lockedHistory_isHiddenFromAccessibilityAndAutomation() {
        launch(seed: "showcase", defaults: locked.merging(["appearanceMode": "dark"]) { $1 }, backdrop: "plain")

        showOverlay(expectingCards: false)

        XCTAssertTrue(element(AccessibilityID.lockOverlay).waitForExistence(timeout: 5), "the lock screen should show")
        XCTAssertEqual(cards.count, 0, "locked cards must not be exposed to accessibility or automation")
        capture("history-locked")
    }

    func test_failedAuthentication_keepsHistoryLocked() {
        launch(defaults: locked)
        showOverlay(expectingCards: false)

        element(AccessibilityID.unlockButton).click()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))

        XCTAssertTrue(element(AccessibilityID.lockOverlay).exists, "history must stay locked after a failed unlock")
        XCTAssertEqual(cards.count, 0)
    }

    func test_successfulAuthentication_revealsHistoryWithoutAClick() {
        launch(defaults: locked.merging(["uitestAuthenticationGranted": "true"]) { $1 })
        showOverlay(expectingCards: false)

        XCTAssertTrue(
            cards.firstMatch.waitForExistence(timeout: 10),
            "the prompt should open by itself, so history shows without pressing the unlock button"
        )
        XCTAssertFalse(element(AccessibilityID.lockOverlay).exists)
    }

    func test_lockedQuickMenu_opensTheLockScreenInstead() {
        launch(defaults: locked)

        send(.showQuickMenu)

        XCTAssertTrue(element(AccessibilityID.lockOverlay).waitForExistence(timeout: 10), "the lock screen should show")
        XCTAssertFalse(element(AccessibilityID.quickMenuPanel).exists, "the quick menu must not bypass the lock")
        XCTAssertEqual(cards.count, 0)
    }

    func test_withoutTheLock_historyShowsAsBefore() {
        launch()

        showOverlay()

        XCTAssertFalse(element(AccessibilityID.lockOverlay).exists)
    }
}
