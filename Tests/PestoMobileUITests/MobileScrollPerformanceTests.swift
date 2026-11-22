// SPDX-License-Identifier: MIT
import UIKit
import XCTest

/// iOS scroll hitch and memory benchmark (`XCTOSSignpostMetric.scrollDecelerationMetric` + `XCTMemoryMetric`).
@MainActor
final class MobileScrollPerformanceTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
    }

    func test_whenScrollingLargeGrid_thenScrollDecelerationAndMemoryAreMeasured() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["PESTO_UITEST_SESSION"] = "mobile-perf-\(UUID().uuidString)"
        app.launchEnvironment["PESTO_UITEST_SEED"] = "large"
        app.launchEnvironment["PESTO_UITEST_DEFAULT_appearanceMode"] = "light"
        app.launch()

        let grid = app.scrollViews
            .matching(NSPredicate(format: "identifier != %@", MobileAccessibilityID.chipRow))
            .firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: 20))

        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(
            metrics: [
                XCTOSSignpostMetric.scrollDecelerationMetric,
                XCTCPUMetric(application: app),
                XCTMemoryMetric(application: app)
            ],
            options: options
        ) {
            grid.swipeUp(velocity: .fast)
            grid.swipeDown(velocity: .fast)
        }
    }
}
