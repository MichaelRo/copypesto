// SPDX-License-Identifier: MIT
import Foundation

/// Waits, on the main actor, for something that SwiftUI builds a moment after it is asked for.
public enum PollUntil {
    /// Checks `condition` now and then every `interval` until it holds or `timeout` has passed.
    @MainActor
    public static func holds(
        timeout: Duration, interval: Duration, _ condition: @MainActor () -> Bool
    )
    async -> Bool {
        if condition() { return true }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            try? await Task.sleep(for: interval)
            if condition() { return true }
        }
        return false
    }
}
