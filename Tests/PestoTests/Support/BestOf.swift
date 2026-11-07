// SPDX-License-Identifier: MIT
import Foundation

/// A test that guards a time budget (an adversarial input must not blow up) runs inside a parallel test run, where one
/// stall from the other tests reads as a slow operation. A run that is over its budget is repeated, and the fastest
/// counts: a real blow-up is slow every time, a stall is not.
enum BestOf {
    static let reruns = 4

    static func measure(budget: Duration, _ work: () -> Void) -> Duration {
        let first = ContinuousClock().measure(work)
        return within(budget, first: first, rerun: work)
    }

    /// `first` is what the caller already measured; nothing runs again when it is within `budget`.
    static func within(_ budget: Duration, first: Duration, rerun: () -> Void) -> Duration {
        guard first > budget else { return first }
        let clock = ContinuousClock()
        return (0..<reruns).reduce(first) { best, _ in min(best, clock.measure(rerun)) }
    }
}
