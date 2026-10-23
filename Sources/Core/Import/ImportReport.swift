// SPDX-License-Identifier: MIT
import Foundation

/// What an import of another app's library comes to, for the line the person reads afterwards: how many clips came
/// in, how many were left out, and how many of those that came in are older than the history Pesto keeps, which the
/// next cleanup removes (clips in a pinboard are pinned and never go).
public struct ImportReport: Equatable, Sendable {
    public let imported: Int
    public let skipped: Int
    public let expiring: Int

    public init(
        summary: PasteMigrator.Summary,
        librarySkipped: Int = 0,
        records: [PasteImportRecord],
        retention: RetentionPolicy,
        now: Date = .now
    ) {
        imported = summary.imported
        skipped = summary.skipped + librarySkipped
        let cutoff = now.addingTimeInterval(-retention.maxAge)
        let older = records.count(where: { $0.pinboard == nil && $0.timestamp < cutoff })
        expiring = min(older, summary.imported)
    }
}
