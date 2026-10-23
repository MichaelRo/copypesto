// SPDX-License-Identifier: MIT
import XCTest

/// The show and hide animations of the overlay, quick menu and pinned window crashed macOS 26 in the past
/// (`_NSWindowTransformAnimation`, overlapping hide and show). Driving them back to back on macOS 27 is the regression
/// check.
final class AnimationStressTests: PestoUITestCase {
    func test_rapidShowAndHide_keepsTheAppAlive() {
        launch()

        for _ in 0..<12 {
            send(.showOverlay)
            RunLoop.current.run(until: Date().addingTimeInterval(0.08))
            send(.hideOverlay)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        send(.showOverlay)

        XCTAssertNotEqual(app.state, .notRunning, "the app crashed while the overlay animated")
        XCTAssertTrue(overlay.waitForExistence(timeout: 10), "the overlay must end up visible after the last show")
    }

    func test_quickMenuAndPinnedWindow_toggleWithoutCrashing() {
        launch()

        for _ in 0..<5 {
            send(.showQuickMenu)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            send(.togglePinnedWindow)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        XCTAssertNotEqual(app.state, .notRunning, "the app crashed while panels animated")
    }
}
