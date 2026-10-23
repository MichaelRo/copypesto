// SPDX-License-Identifier: MIT
import Foundation
import Synchronization

public final class FrontmostHistory: Sendable {
    private static let capacity = 64

    private struct Entry {
        let bundleID: String
        let at: Date
        let changeCount: Int?
    }

    private let entries = Mutex<[Entry]>([])

    public init() {}

    public func record(_ bundleID: String?, at date: Date = .now, changeCount: Int? = nil) {
        guard let bundleID else { return }
        entries.withLock {
            $0.append(Entry(bundleID: bundleID, at: date, changeCount: changeCount))
            if $0.count > Self.capacity { $0.removeFirst($0.count - Self.capacity) }
        }
    }

    /// Every app that was frontmost at some moment in the last `interval` seconds.
    /// If `currentChangeCount` is provided, an app that lost focus before a subsequent copy occurred
    /// is not considered the source of that copy.
    public func bundleIDs(
        within interval: TimeInterval,
        of now: Date = .now,
        currentChangeCount: Int? = nil
    )
    -> [String] {
        entries.withLock { entries in
            entries.indices.compactMap { index in
                let leftAt = entries.indices.contains(index + 1) ? entries[index + 1].at : nil
                guard let leftAt else { return entries[index].bundleID }
                guard now.timeIntervalSince(leftAt) <= interval else { return nil }
                if let currentChangeCount,
                   let nextChangeCount = entries[index + 1].changeCount,
                   currentChangeCount > nextChangeCount
                {
                    return nil
                }
                return entries[index].bundleID
            }
        }
    }
}
