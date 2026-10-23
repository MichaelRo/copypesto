// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import XCTest
@testable import Pesto

/// Measures the latency of PasteCoordinator.executePaste() when no focus target is captured.
///
/// Budget: < 200 ms per call on M1 Air. This is the "fast reject" path — the coordinator
/// attempts app activation, finds no captured target, and returns .requiresManualPaste.
/// It establishes a ceiling on coordinator overhead independently of the AX/CGEvent tiers.
@MainActor
final class PasteCoordinatorPerformanceTests: XCTestCase {
    func test_executePaste_noTarget_resolvesFast() {
        let coordinator = PasteCoordinator()
        measure(metrics: [XCTClockMetric()]) {
            let done = expectation(description: "paste")
            Task { @MainActor in
                _ = await coordinator.executePaste(payload: .text("Hello"))
                done.fulfill()
            }
            waitForExpectations(timeout: 5)
        }
    }
}
