// SPDX-License-Identifier: MIT
import Foundation

public enum SyncError: Error, Equatable, Sendable {
    case clockFarAhead
    case malformed(String)
    case wrongKey
    case badSignature
    case unknownSigner
    case wrongVault
    case wrongEpoch
    case rollback
    case fork
    case brokenChain
    case unsupportedVersion
    case deviceUnknown
}

/// A hybrid logical clock reading: wall time in milliseconds, a counter that breaks ties inside one millisecond (and
/// absorbs a clock that moved back), and the device that made it, so any two stamps order the same way on every Mac.
public struct SyncStamp: Hashable, Comparable, Codable, Sendable {
    public static let farAheadLimit: TimeInterval = 7 * 24 * 3600

    public var wallMillis: UInt64
    public var counter: UInt32
    public var deviceID: String

    public init(wallMillis: UInt64, counter: UInt32, deviceID: String) {
        self.wallMillis = wallMillis
        self.counter = counter
        self.deviceID = deviceID
    }

    public static func < (lhs: SyncStamp, rhs: SyncStamp) -> Bool {
        (lhs.wallMillis, lhs.counter, lhs.deviceID) < (rhs.wallMillis, rhs.counter, rhs.deviceID)
    }

    /// The stamp for a local change made after `last` (this Mac's own latest reading, if any).
    public static func next(after last: SyncStamp?, now: Date, deviceID: String) -> SyncStamp {
        let wall = max(Self.millis(now), last?.wallMillis ?? 0)
        let counter = (last.map { $0.wallMillis == wall ? $0.counter &+ 1 : 0 }) ?? 0
        return SyncStamp(wallMillis: wall, counter: counter, deviceID: deviceID)
    }

    /// This Mac's clock after it has seen `remote`: later than both. A remote reading more than a week ahead of this
    /// Mac's own clock is refused, because it would outrank every later local edit.
    public func receiving(_ remote: SyncStamp, now: Date, deviceID: String) throws -> SyncStamp {
        let nowMillis = Self.millis(now)
        guard Double(remote.wallMillis) / 1000 <= Double(nowMillis) / 1000 + Self.farAheadLimit else {
            throw SyncError.clockFarAhead
        }
        let wall = max(nowMillis, wallMillis, remote.wallMillis)
        let counter: UInt32 = switch (wall == wallMillis, wall == remote.wallMillis) {
        case (true, true): max(self.counter, remote.counter) &+ 1
        case (true, false): self.counter &+ 1
        case (false, true): remote.counter &+ 1
        case (false, false): 0
        }
        return SyncStamp(wallMillis: wall, counter: counter, deviceID: deviceID)
    }

    /// Fixed-width hex, so the strings sort the way the stamps do: `wall(16)-counter(8)-device`.
    public var encoded: String {
        String(format: "%016llx-%08x-%@", wallMillis, counter, deviceID)
    }

    public init?(encoded: String) {
        let parts = encoded.split(separator: "-", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 16, parts[1].count == 8,
              let wall = UInt64(parts[0], radix: 16), let counter = UInt32(parts[1], radix: 16) else { return nil }
        self.init(wallMillis: wall, counter: counter, deviceID: String(parts[2]))
    }

    public static func millis(_ date: Date) -> UInt64 {
        UInt64(max(0, date.timeIntervalSince1970 * 1000))
    }
}
