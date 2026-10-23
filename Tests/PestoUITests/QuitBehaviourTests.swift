// SPDX-License-Identifier: MIT
import XCTest

/// Audit P-06: "Clear history on quit" waited on a semaphore on the main thread for a Task that could only
/// run on the main thread, so quitting hung for three seconds and nothing was cleared.
final class QuitBehaviourTests: PestoUITestCase {
    func test_clearOnQuit_clearsTheHistoryAndQuitsPromptly() {
        launch(defaults: ["hasOnboarded": "true", "clearOnQuit": "true"])

        quitFromStatusMenu()

        let delay = terminationDelay()
        XCTAssertNotNil(delay, "the app never reached willTerminate")
        XCTAssertLessThan(delay ?? .infinity, 3, "quitting waited \(delay ?? -1) s before terminating")
        XCTAssertEqual(storedItemCount(), 0, "history should be cleared when quitting with clearOnQuit on")
    }

    func test_withoutClearOnQuit_theHistorySurvivesQuitting() {
        launch()

        quitFromStatusMenu()

        XCTAssertNotNil(terminationDelay(), "the app never reached willTerminate")
        XCTAssertEqual(storedItemCount(), 14, "the seeded history must be untouched")
    }
}
