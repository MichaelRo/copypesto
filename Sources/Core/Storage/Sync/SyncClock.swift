// SPDX-License-Identifier: MIT
import Foundation
import Synchronization

/// This Mac's hybrid logical clock for sync: one per store, persisted so a stamp is never reused after a restart, and
/// later than every stamp it has seen.
public final class SyncClock: Sendable {
    public static let defaultsKey = "syncClockHighWater"

    private let deviceID: String
    /// `UserDefaults` is documented thread-safe; it is not marked `Sendable`.
    private nonisolated(unsafe) let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let last: Mutex<SyncStamp?>

    public init(
        deviceID: String,
        defaults: UserDefaults = AppDefaults.store,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.deviceID = deviceID
        self.defaults = defaults
        self.now = now
        last = Mutex(defaults.string(forKey: Self.defaultsKey).flatMap(SyncStamp.init(encoded:)))
    }

    /// The stamp for a change made on this Mac now.
    public func next() -> SyncStamp {
        last.withLock { last in
            let stamp = SyncStamp.next(after: last, now: now(), deviceID: deviceID)
            last = stamp
            defaults.set(stamp.encoded, forKey: Self.defaultsKey)
            return stamp
        }
    }

    /// Notes a stamp read from another Mac, so the next local change is later than it. Refuses one from the far future.
    public func observe(_ remote: SyncStamp) throws {
        try last.withLock { last in
            let merged = try (last ?? SyncStamp(wallMillis: 0, counter: 0, deviceID: deviceID))
                .receiving(remote, now: now(), deviceID: deviceID)
            last = merged
            defaults.set(merged.encoded, forKey: Self.defaultsKey)
        }
    }
}
