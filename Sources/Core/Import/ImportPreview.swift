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

    public init(
        appName: String, pinned: [PasteImportRecord], history: [PasteImportRecord], skipped: Int, pinSummary: String?
    ) {
        self.appName = appName
        self.pinned = pinned
        self.history = history
        self.skipped = skipped
        self.pinSummary = pinSummary
    }

    public init(paste library: PasteLibrary) {
        self.init(
            appName: "Paste",
            pinned: library.pinboards.flatMap(\.records),
            history: library.history,
            skipped: 0,
            pinSummary: library.pinboardClipCount > 0 ? library.pinboardSummary : nil
        )
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
        pinned.count
    }

    public var historyCount: Int {
        history.count
    }

    public var hasPins: Bool {
        !pinned.isEmpty
    }

    public var isEmpty: Bool {
        pinned.isEmpty && history.isEmpty
    }

    public var oldest: Date? {
        (pinned + history).map(\.timestamp).min()
    }

    public func records(includingHistory: Bool) -> [PasteImportRecord] {
        pinned + (includingHistory ? history : [])
    }

    /// How many imported history clips are older than the history Pesto keeps, so the next cleanup removes them (a
    /// pinned
    /// clip never goes). Same rule as `ImportReport`, known before the person decides.
    public func expiring(retention: RetentionPolicy, now: Date = .now, includingHistory: Bool) -> Int {
        guard includingHistory else { return 0 }
        let cutoff = now.addingTimeInterval(-retention.maxAge)
        return history.count(where: { $0.timestamp < cutoff })
    }
}
