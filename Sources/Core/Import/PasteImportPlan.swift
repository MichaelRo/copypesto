// SPDX-License-Identifier: MIT
import Foundation

// swiftlint:disable:next large_tuple
public typealias ExistingClip = (UUID, Date, Int)

/// How much one import takes in: the clips it keeps and the payload bytes they hold.
public struct ImportCap: Sendable, Equatable {
    public let maxClips: Int
    public let maxBytes: Int

    public init(maxClips: Int, maxBytes: Int) {
        self.maxClips = maxClips
        self.maxBytes = maxBytes
    }

    public static let paste = ImportCap(maxClips: 20_000, maxBytes: 1_000_000_000)
}

/// Which clips of a Paste library an import takes, decided from each clip's size and date alone, so the library is
/// never held in memory (ADR 0032). Pinboards come first, in Paste's order; then history, newest first. The first clip
/// that does not fit ends the list, so "the newest N" is exactly that. What Pesto's own retention setting would remove
/// again at the next cleanup is not imported either.
public struct PasteImportPlan: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let snippetKey: Int64
        public let dataKey: Int64
        public let bytes: Int
        public let timestamp: Date
        public let pinboard: String?

        public init(snippetKey: Int64, dataKey: Int64, bytes: Int, timestamp: Date, pinboard: String?) {
            self.snippetKey = snippetKey
            self.dataKey = dataKey
            self.bytes = bytes
            self.timestamp = timestamp
            self.pinboard = pinboard
        }
    }

    public let pinboards: [Entry]
    public let history: [Entry]
    public let libraryClips: Int
    public let unusable: Int
    public let pinboardsLeftByCap: Int
    public let historyLeftByCap: Int
    public let historyLeftByRetention: Int
    public let displacedExisting: Int
    /// History clips with the same copy time as a clip Pesto already holds: the same clip, imported before. They are
    /// not imported again and do not count against retention. Found by time alone, so a clip Pesto has moved to the
    /// front since is not recognised here and is skipped by `ingest` instead.
    public var alreadyInPesto = 0

    public var selectedCount: Int {
        pinboards.count + history.count
    }

    public var leftByLimits: Int {
        pinboardsLeftByCap + historyLeftByCap + historyLeftByRetention
    }

    public var isLimited: Bool {
        leftByLimits > 0
    }

    public var pinSummary: String? {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for name in pinboards.compactMap(\.pinboard) {
            if counts[name] == nil { order.append(name) }
            counts[name, default: 0] += 1
        }
        return order.isEmpty ? nil : order.map { "\($0) (\(counts[$0] ?? 0))" }.joined(separator: ", ")
    }

    /// What the one-line summary names after "will be imported:".
    public enum Lead: Equatable, Sendable {
        case pinboardsAndNewest(Int)
        case pinboards
        case newest(Int)
        case nothing
        case firstPinboards(Int)
    }

    /// The clips to read, pinboards first and then history, in groups that each hold at most `maxRecords` clips and
    /// `maxBytes` of payload (a single clip larger than that is a group of its own), so reading never holds more
    /// than one group.
    public func batches(
        includingHistory: Bool,
        maxRecords: Int = PasteLibrarySnapshot.batchRecords,
        maxBytes: Int = PasteLibrarySnapshot.batchBytes
    )
    -> [[Entry]] {
        var groups: [[Entry]] = []
        var current: [Entry] = []
        var currentBytes = 0
        for entry in pinboards + (includingHistory ? history : []) {
            if !current.isEmpty, current.count >= maxRecords || currentBytes + entry.bytes > maxBytes {
                groups.append(current)
                current = []
                currentBytes = 0
            }
            current.append(entry)
            currentBytes += entry.bytes
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    public func selectedCount(includingHistory: Bool) -> Int {
        pinboards.count + (includingHistory ? history.count : 0)
    }

    /// History is the person's choice when there are pinboards (ADR 0011), so with the choice off only pinboards are
    /// named. Pinboards cut by the cap leave no room for history at all.
    public func lead(includingHistory: Bool) -> Lead {
        if pinboardsLeftByCap > 0 { return .firstPinboards(pinboards.count) }
        if pinboards.isEmpty { return history.isEmpty ? .nothing : .newest(history.count) }
        return includingHistory && !history.isEmpty ? .pinboardsAndNewest(history.count) : .pinboards
    }
}

/// Feeds a plan one row at a time. A row that is not in a pinboard goes in `addHistory`, newest first.
public struct PasteImportPlanner: Sendable {
    public struct Row: Sendable {
        public let snippetKey: Int64
        public let dataKey: Int64?
        public let bytes: Int?
        public let timestamp: Date
        public let pinboard: String?

        public init(snippetKey: Int64, dataKey: Int64?, bytes: Int?, timestamp: Date, pinboard: String?) {
            self.snippetKey = snippetKey
            self.dataKey = dataKey
            self.bytes = bytes
            self.timestamp = timestamp
            self.pinboard = pinboard
        }
    }

    private let cap: ImportCap
    private let maxRecordBytes: Int
    private var pinboards: [PasteImportPlan.Entry] = []
    private var history: [PasteImportPlan.Entry] = []
    private var pinboardKeys = Set<Int64>()
    private var historyKeys = Set<Int64>()
    private var usedBytes = 0
    private var closed = false
    private var unusable = 0
    private var pinboardsLeft = 0
    private var historyLeft = 0

    public init(cap: ImportCap = .paste, maxRecordBytes: Int = PasteLibraryReader.maxRecordBytes) {
        self.cap = cap
        self.maxRecordBytes = maxRecordBytes
    }

    public mutating func addPinboard(_ row: Row) {
        guard pinboardKeys.insert(row.snippetKey).inserted else { return }
        guard let entry = usable(row, pinboard: row.pinboard) else { return }
        if take(entry) { pinboards.append(entry) } else { pinboardsLeft += 1 }
    }

    public mutating func addHistory(_ row: Row) {
        guard !pinboardKeys.contains(row.snippetKey), historyKeys.insert(row.snippetKey).inserted else { return }
        guard let entry = usable(row, pinboard: nil) else { return }
        if take(entry) { history.append(entry) } else { historyLeft += 1 }
    }

    /// The plan, once retention has had its say. `existing` is every unpinned clip already in Pesto, as the pruner
    /// reads it: id, date, size.
    public func plan(
        retention: RetentionPolicy,
        existing: [ExistingClip] = [],
        now: Date = .now
    )
    -> PasteImportPlan {
        let storedTimes = Set(existing.map(\.1.timeIntervalSinceReferenceDate))
        let alreadyThere = history.count(where: { storedTimes.contains($0.timestamp.timeIntervalSinceReferenceDate) })
        let fresh = history.filter { !storedTimes.contains($0.timestamp.timeIntervalSinceReferenceDate) }
        let freshIDs = fresh.map { _ in UUID() }
        var candidates = existing
        for (index, entry) in fresh.enumerated() {
            candidates.append((freshIDs[index], entry.timestamp, entry.bytes))
        }
        candidates.sort { $0.1 < $1.1 }
        let evicted = Set(RetentionPruner.computeEvictions(candidates: candidates, policy: retention, now: now))
        let kept = fresh.enumerated().filter { !evicted.contains(freshIDs[$0.offset]) }.map(\.element)
        return PasteImportPlan(
            pinboards: pinboards,
            history: kept,
            libraryClips: pinboardKeys.count + historyKeys.count,
            unusable: unusable,
            pinboardsLeftByCap: pinboardsLeft,
            historyLeftByCap: historyLeft,
            historyLeftByRetention: fresh.count - kept.count,
            displacedExisting: existing.count(where: { evicted.contains($0.0) }),
            alreadyInPesto: alreadyThere
        )
    }

    private mutating func usable(_ row: Row, pinboard: String?) -> PasteImportPlan.Entry? {
        guard let dataKey = row.dataKey, let bytes = row.bytes, bytes > 0, bytes <= maxRecordBytes else {
            unusable += 1
            return nil
        }
        return .init(
            snippetKey: row.snippetKey, dataKey: dataKey, bytes: bytes, timestamp: row.timestamp,
            pinboard: pinboard
        )
    }

    private mutating func take(_ entry: PasteImportPlan.Entry) -> Bool {
        guard !closed else { return false }
        guard pinboards.count + history.count < cap.maxClips, usedBytes + entry.bytes <= cap.maxBytes else {
            closed = true
            return false
        }
        usedBytes += entry.bytes
        return true
    }
}
