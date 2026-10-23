// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import XCTest
@testable import Pesto

/// Measures the synchronous overhead of opening the overlay (show() through first makeKeyAndOrderFront).
///
/// Budget: < 100 ms on M1 Air. The 0.25 s spring animation is intentional and excluded —
/// only the synchronous setup path (frame calculation, NSHostingView layout, panel ordering)
/// is measured here.
///
/// It has no history of 5,000 clips and no copy made while the shelf was closed, so it stayed at 40 ms while the real
/// app took 124 ms (P-01; the retention sweep that cost 78 ms of it no longer runs at open). The open budget of the
/// real app is `ShelfOpenLatencyTests` in the gate (the real shelf over 5,000 clips, after a copy made while it was
/// closed, on the Debug build) and `make bench-latency open` (a Profile build, the hotkey path), which a release does
/// not skip (`docs/testing.md`, "Before a release").
@MainActor
final class OverlayPerformanceTests: XCTestCase {
    func test_overlayOpen_synchronousSetupUnder100ms() {
        let appState = AppState()
        // Baseline: the synchronous path through show() should be well under 100 ms.
        // If this regresses, profile BottomShelfPositioning.frame() and NSHostingView layout.
        let clock = ContinuousClock()
        let warmUp = OverlayWindowController(appState: appState)
        warmUp.show()
        warmUp.hide()
        let elapsed = clock.measure {
            let wc = OverlayWindowController(appState: appState)
            wc.show()
            CATransaction.flush()
            wc.hide()
        }
        if !RunEnvironment.isCI {
            XCTAssertLessThan(
                elapsed,
                .milliseconds(100),
                "overlay open budget (measured about 40 ms on an M-series Mac)"
            )
        }

        measure(metrics: [XCTClockMetric()]) {
            let wc = OverlayWindowController(appState: appState)
            wc.show()
            // Flush the compositor so the first frame has been submitted before we stop timing.
            CATransaction.flush()
            wc.hide()
        }
    }
}
