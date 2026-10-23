// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

/// AppDelegate kept ONE task handle. A second paste overwrote the first without
/// cancelling it, and when the first finished it cleared the handle of the second, so a later sleep/wake found
/// nothing to cancel and the second paste fired into whatever app was focused on return.
@MainActor
@Suite("PasteTaskTracker")
struct PasteTaskTrackerTests {
    private func waitUntil(_ condition: () -> Bool, timeout: Duration = .seconds(2)) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Runs until cancelled, then records that it saw the cancellation.
    private func lingering(_ log: Log, _ name: String) -> @MainActor () async -> Void {
        {
            log.entries.append("\(name) started")
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(5))
            }
            log.entries.append("\(name) cancelled")
        }
    }

    @MainActor
    final class Log {
        var entries: [String] = []
    }

    @Test("starting a paste cancels the one still in flight")
    func start_cancelsThePreviousPaste() async {
        let tracker = PasteTaskTracker()
        let log = Log()
        tracker.start(lingering(log, "first"))
        await waitUntil { log.entries.contains("first started") }

        tracker.start(lingering(log, "second"))
        await waitUntil { log.entries.contains("first cancelled") }

        #expect(log.entries.contains("first cancelled"))
        tracker.interrupt()
    }

    @Test("an old paste finishing does not clear the handle of the newer one")
    func oldPasteFinishing_doesNotForgetTheNewOne() async {
        let tracker = PasteTaskTracker()
        let log = Log()
        tracker.start(lingering(log, "first"))
        await waitUntil { log.entries.contains("first started") }
        tracker.start(lingering(log, "second"))
        await waitUntil { log.entries.contains("first cancelled") && log.entries.contains("second started") }

        // The first task has now ended. The second must still be tracked, so a wake can cancel it.
        #expect(tracker.isRunning)
        tracker.interrupt()
        await waitUntil { log.entries.contains("second cancelled") }
        #expect(log.entries.contains("second cancelled"))
        #expect(!tracker.isRunning)
    }

    @Test("interrupting cancels the paste in flight")
    func interrupt_cancelsThePasteInFlight() async {
        let tracker = PasteTaskTracker()
        let log = Log()
        tracker.start(lingering(log, "only"))
        await waitUntil { log.entries.contains("only started") }

        tracker.interrupt()
        await waitUntil { log.entries.contains("only cancelled") }

        #expect(log.entries.contains("only cancelled"))
        #expect(!tracker.isRunning)
    }

    @Test("a paste requested before a sleep or lock is refused if it starts after it")
    func startAfterInterruption_isRefusedForAnOlderRequest() async {
        let tracker = PasteTaskTracker()
        let requestedAt = tracker.interruptionEpoch
        tracker.interrupt()
        var ran = false

        let started = tracker.start(requestedAtEpoch: requestedAt) { ran = true }
        try? await Task.sleep(for: .milliseconds(50))

        #expect(!started)
        #expect(!ran, "a phantom paste must not fire after the Mac slept between selection and paste")
    }

    @Test("a paste requested after the latest interruption runs normally")
    func startWithCurrentEpoch_runs() async {
        let tracker = PasteTaskTracker()
        tracker.interrupt()
        var ran = false

        let started = tracker.start(requestedAtEpoch: tracker.interruptionEpoch) { ran = true }
        await waitUntil { ran }

        #expect(started)
        #expect(ran)
        await waitUntil { !tracker.isRunning }
        #expect(!tracker.isRunning, "a finished paste leaves nothing to cancel")
    }
}
