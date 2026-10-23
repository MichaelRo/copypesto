// SPDX-License-Identifier: MIT
import Foundation
import Synchronization

/// How many copies Pesto refused to keep. Counts only: what was copied, and which app it came from, are never stored.
public struct PrivacyStats: Codable, Sendable, Equatable {
    public var excludedAppBlocks = 0
    public var concealedBlocks = 0
    public var remoteBlocks = 0
    /// When counting began (the first block), so "since" means something.
    public var since: Date?

    public var total: Int {
        excludedAppBlocks + concealedBlocks + remoteBlocks
    }

    public init() {}

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        excludedAppBlocks = try values.decodeIfPresent(Int.self, forKey: .excludedAppBlocks) ?? 0
        concealedBlocks = try values.decodeIfPresent(Int.self, forKey: .concealedBlocks) ?? 0
        remoteBlocks = try values.decodeIfPresent(Int.self, forKey: .remoteBlocks) ?? 0
        since = try values.decodeIfPresent(Date.self, forKey: .since)
    }
}

public final class PrivacyStatsStore: Sendable {
    public static let defaultsKey = "privacyStats"

    /// One lock around every read and write of the stored counts, so two blocked copies never lose an update.
    private let defaults: Mutex<Box>

    /// `UserDefaults` is documented as thread-safe; the lock orders our read-modify-write sequences, not its storage.
    private struct Box: @unchecked Sendable {
        let defaults: UserDefaults
    }

    public init(defaults: UserDefaults = AppDefaults.store) {
        self.defaults = Mutex(Box(defaults: defaults))
    }

    public var stats: PrivacyStats {
        defaults.withLock { Self.load($0.defaults) }
    }

    public func record(_ reason: ExclusionRules.BlockReason, now: Date = .now) {
        defaults.withLock { box in
            var current = Self.load(box.defaults)
            switch reason {
            case .excludedApp: current.excludedAppBlocks += 1
            case .concealedMarker: current.concealedBlocks += 1
            case .remoteCopy: current.remoteBlocks += 1
            }
            if current.since == nil { current.since = now }
            Self.save(current, to: box.defaults)
        }
    }

    public func reset() {
        defaults.withLock { $0.defaults.removeObject(forKey: Self.defaultsKey) }
    }

    private static func load(_ defaults: UserDefaults) -> PrivacyStats {
        guard let data = defaults.data(forKey: defaultsKey),
              let stats = try? JSONDecoder().decode(PrivacyStats.self, from: data) else { return PrivacyStats() }
        return stats
    }

    private static func save(_ stats: PrivacyStats, to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(stats) { defaults.set(data, forKey: defaultsKey) }
    }
}
