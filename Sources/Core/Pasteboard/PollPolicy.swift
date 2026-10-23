// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation

/// How often the watcher looks at the pasteboard. A copy follows a key press or a click, so the watcher looks every
/// 60 ms for three seconds after the last one (the wait for a copy to be noticed was 100 ms on average at a flat 200
/// ms),
/// keeps the usual 200 ms while the person is around, and drops to 500 ms once they have been away for half a minute.
/// The CPU budget (`AGENTS.md`) is for an idle watcher, which is the slowest of the three.
public enum PollPolicy {
    public static func period(secondsSinceInput: TimeInterval) -> Duration {
        switch secondsSinceInput {
        case ..<3: .milliseconds(60)
        case ..<30: .milliseconds(200)
        default: .milliseconds(500)
        }
    }

    /// Seconds since the last key, click or pointer movement, from the system.
    public static func systemSecondsSinceInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0) ?? .null)
    }
}
