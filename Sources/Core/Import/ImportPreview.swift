// SPDX-License-Identifier: MIT
import Foundation

/// What another app's library holds, in the one shape the import sheet shows for every source (Paste, Maccy, Alfred):
/// the clips that were pinned there, the history, and how many entries the reader could not use. Nothing is imported
/// until the person confirms.
public struct ImportPreview: Sendable {
    public let appName: String
    public let pinned: [PasteImportRecord]
    public let history: [PasteImportRecord]
    public let skipped: Int
    public let pinSummary: String?
    /// Set for a Paste library read in pieces: which clips the import takes and why the others stay. `pinned` and
    /// `history` are empty then, and `snapshot` is where the import reads the clips from (nil for a picture or test).
    public let plan: PasteImportPlan?
    public let snapshot: PasteLibrarySnapshot?

    public init(
        appName: String, pinned: [PasteImportRecord], history: [PasteImportRecord], skipped: Int, pinSummary: String?
    ) {
        self.appName = appName
        self.pinned = pinned
        self.history = history
        self.skipped = skipped
        self.pinSummary = pinSummary
        plan = nil
        snapshot = nil
    }

    public init(paste plan: PasteImportPlan, snapshot: PasteLibrarySnapshot?) {
        appName = "Paste"
        pinned = []
        history = []
        skipped = plan.unusable
        pinSummary = plan.pinSummary
        self.plan = plan
        self.snapshot = snapshot
    }

    public init(appName: String, library: ClipboardAppLibrary) {
        let pinned = library.records.filter { $0.pinboard != nil }
        var order: [String] = []
        var counts: [String: Int] = [:]
        for name in pinned.compactMap(\.pinboard) {
            if counts[name] == nil { order.append(name) }
            counts[name, default: 0] += 1
        }
        self.init(
            appName: appName,
            pinned: pinned,
            history: library.records.filter { $0.pinboard == nil },
            skipped: library.skipped,
            pinSummary: order.isEmpty ? nil : order.map { "\($0) (\(counts[$0] ?? 0))" }.joined(separator: ", ")
        )
    }

    public var pinnedCount: Int {
        plan?.pinboards.count ?? pinned.count
    }

    public var historyCount: Int {
        plan?.history.count ?? history.count
    }

    public var hasPins: Bool {
        pinnedCount > 0
    }

    public var isEmpty: Bool {
        pinnedCount == 0 && historyCount == 0
    }

    public var oldest: Date? {
        if let plan { return (plan.pinboards + plan.history).map(\.timestamp).min() }
        return (pinned + history).map(\.timestamp).min()
    }

    public func importCount(includingHistory: Bool) -> Int {
        if let plan { return plan.selectedCount(includingHistory: includingHistory) }
        return pinned.count + (includingHistory ? history.count : 0)
    }

    public func records(includingHistory: Bool) -> [PasteImportRecord] {
        pinned + (includingHistory ? history : [])
    }

    /// How many imported history clips are older than the history Pesto keeps, so the next cleanup removes them (a
    /// pinned
    /// clip never goes). Same rule as `ImportReport`, known before the person decides.
    public func expiring(retention: RetentionPolicy, now: Date = .now, includingHistory: Bool) -> Int {
        guard includingHistory, plan == nil else { return 0 }
        let cutoff = now.addingTimeInterval(-retention.maxAge)
        return history.count(where: { $0.timestamp < cutoff })
    }
}
