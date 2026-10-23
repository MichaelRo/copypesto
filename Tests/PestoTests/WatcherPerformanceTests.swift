// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import XCTest

/// A minimal PasteboardReading stub whose changeCount never advances — simulates an idle
/// pasteboard so the watcher does no real work during the CPU measurement.
private final class IdlePasteboard: PasteboardReading, @unchecked Sendable {
    let changeCount = 0
    func types() -> [NSPasteboard.PasteboardType] {
        []
    }

    func data(forType _: NSPasteboard.PasteboardType) -> Data? {
        nil
    }

    func string(forType _: NSPasteboard.PasteboardType) -> String? {
        nil
    }
}

/// Measures the background CPU footprint of a running PasteboardWatcher with no activity.
///
/// Budget: under 0.5% of one core on average (200 ms poll interval, background QoS), asserted on a developer Mac only.
/// If this regresses, check for spurious timer wakeups or lock contention.
final class WatcherPerformanceTests: XCTestCase {
    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ time: timeval) -> Double {
            Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000
        }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    func test_watcherIdle_cpuBudget() async throws {
        try await measureIdleWatcher(period: .milliseconds(200), budget: 0.5)
    }

    /// The fast tier `PollPolicy` uses for 3 s after a key press or click, so continuous typing keeps the watcher
    /// here (P-05). It does no more work per second than at 200 ms because a tick starts only for a board that moved.
    func test_watcherIdle_fastTier_cpuBudget() async throws {
        try await measureIdleWatcher(period: .milliseconds(60), budget: 0.5)
    }

    private func measureIdleWatcher(period: Duration, budget: Double) async throws {
        let watcher = PasteboardWatcher(pasteboard: IdlePasteboard())
        await watcher.start(period: period)
        try await Task.sleep(for: .milliseconds(500))

        // The figure is the whole process's CPU time, and earlier tests leave background work behind (a run of the full
        // hosted suite measured 1% here where the watcher alone costs 0.25%). Four short windows are measured and the
        // quietest counts: leftover work comes and goes, a watcher that really costs too much does in every window.
        let window = 3.0
        var quietest = Double.infinity
        var usedMilliseconds = 0.0
        for _ in 0..<4 {
            let before = Self.cpuSeconds()
            try await Task.sleep(for: .seconds(window))
            let used = Self.cpuSeconds() - before
            if used / window * 100 < quietest {
                quietest = used / window * 100
                usedMilliseconds = used * 1000
            }
            if quietest < budget { break }
        }
        await watcher.stop()

        let note = XCTAttachment(
            string: "idle watcher at \(period): \(usedMilliseconds) ms of CPU in \(window) s = \(quietest)%"
        )
        note.lifetime = .keepAlways
        add(note)
        PerfReport.emit(
            "watcher idle at \(period): \(quietest)% of a core (\(usedMilliseconds) ms in \(window) s, quietest window)"
        )
        if !RunEnvironment.isCI {
            XCTAssertLessThan(quietest, budget, "an idle watcher used \(quietest)% of a core (budget \(budget)%)")
        }
    }
}
