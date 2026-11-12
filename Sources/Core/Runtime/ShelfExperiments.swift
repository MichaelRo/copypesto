// SPDX-License-Identifier: MIT
import Observation

/// Names of changes a benchmark switches on and off while the app runs, so two ways of drawing a card are timed in the
/// same launch, alternately, and the noise between launches cancels (`benchCycleAB`). Empty everywhere else: only the
/// bench drive ever sets it.
@MainActor
@Observable
public final class ShelfExperiments {
    public static let shared = ShelfExperiments()

    public private(set) var active: Set<String> = []

    public func set(_ flags: Set<String>) {
        active = flags
    }

    public func isOn(_ flag: String) -> Bool {
        active.contains(flag)
    }
}
