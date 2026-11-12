// SPDX-License-Identifier: MIT
import Foundation

/// How long a change took to reach the screen, as the main run loop sees it: from `start` to the end of the pass that
/// follows Core Animation's commit (observer order 2,100,000, as `PerfInterval.endAfterNextCommit` does). No private
/// API.
public enum CommitClock {
    @MainActor
    public static func afterNextCommit(
        from start: ContinuousClock.Instant,
        _ completion: @escaping @MainActor (Double) -> Void
    ) {
        let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault, CFRunLoopActivity.beforeWaiting.rawValue, false, 2_100_000
        ) { _, _ in
            let elapsed = ContinuousClock.now - start
            let millis = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
            MainActor.assumeIsolated { completion(millis) }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }
}
