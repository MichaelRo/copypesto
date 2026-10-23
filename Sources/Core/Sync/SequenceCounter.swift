// SPDX-License-Identifier: MIT
import Foundation

/// Monotonic per-device sequence number. Used as a tiebreaker for cross-device ordering.
///
/// Persisted to `UserDefaults` on every increment — cheap and durable. Across crashes
/// we may lose at most one value, which is fine: ordering ties are already broken by
/// `deviceID` as the final tiebreaker.
public actor SequenceCounter {
    public static let defaultDefaultsKey = "\(AppIdentity.bundleID).sequenceNumber"

    private let defaults: UserDefaults
    private let key: String
    private var current: Int64

    public init(defaults: UserDefaults = .standard, key: String = defaultDefaultsKey) {
        self.defaults = defaults
        self.key = key
        let raw = defaults.object(forKey: key) as? NSNumber
        self.current = raw?.int64Value ?? 0
    }

    public func next() -> Int64 {
        current &+= 1
        defaults.set(NSNumber(value: current), forKey: key)
        return current
    }

    public var peekCurrent: Int64 {
        current
    }

    /// Test-only: reset the counter to a known value.
    public func reset(to value: Int64) {
        current = value
        defaults.set(NSNumber(value: current), forKey: key)
    }
}
