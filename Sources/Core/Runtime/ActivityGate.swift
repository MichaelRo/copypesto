// SPDX-License-Identifier: MIT
import Foundation
import Synchronization

/// Work that can wait asks this before it starts, and the shelf tells it when the person is scrolling or holding an
/// arrow
/// key. A link preview's fetch ends in a re-sealed record, a save and a rebuild of the history index, all on the main
/// thread; started in the middle of a scroll, that is the stutter. Nothing is cancelled or skipped: the fetch starts
/// when the shelf has been still for the quiet period, so the preview arrives a beat after the scroll stops.
public final class ActivityGate: Sendable {
    public static let shared = ActivityGate()

    private let quietPeriod: Duration
    private let lastActivity = Mutex<ContinuousClock.Instant?>(nil)

    public init(quietPeriod: Duration = .milliseconds(250)) {
        self.quietPeriod = quietPeriod
    }

    public func noteActivity() {
        lastActivity.withLock { $0 = .now }
    }

    /// Returns once nothing has happened for the quiet period, or when the calling task is cancelled.
    public func waitUntilQuiet() async {
        while !Task.isCancelled {
            guard let last = lastActivity.withLock({ $0 }) else { return }
            let remaining = quietPeriod - (ContinuousClock.now - last)
            if remaining <= .zero { return }
            try? await Task.sleep(for: remaining)
        }
    }
}
