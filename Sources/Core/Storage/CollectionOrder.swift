// SPDX-License-Identifier: MIT
import Foundation

/// How a plain collection lists its clips: the ones the person placed by hand first, in that order, then the rest,
/// by when they were first copied, newest first, so a paste does not move a clip inside a collection (only the
/// history puts it in front). The hand order lives in sealed metadata, so it is read once per clip rather than inside
/// the comparison, which read it about 20,000 times to sort 1,000 clips.
public enum CollectionOrder {
    private struct Keyed {
        let item: ClipboardItem
        let order: Int
        let copiedAt: Date
    }

    public static func sorted(_ items: [ClipboardItem]) -> [ClipboardItem] {
        items
            .map { item in
                let metadata = item.metadata
                return Keyed(
                    item: item, order: metadata.collectionOrder ?? Int.max,
                    copiedAt: metadata.copiedAt ?? item.timestamp
                )
            }
            .sorted { a, b in
                if a.order != b.order { return a.order < b.order }
                if a.copiedAt != b.copiedAt { return a.copiedAt > b.copiedAt }
                return a.item.id.uuidString < b.item.id.uuidString
            }
            .map(\.item)
    }

    public static func sortedRows(_ rows: [HistoryRow]) -> [HistoryRow] {
        rows.sorted { a, b in
            let orderA = a.collectionOrder ?? Int.max
            let orderB = b.collectionOrder ?? Int.max
            if orderA != orderB { return orderA < orderB }
            if a.copiedAt != b.copiedAt { return a.copiedAt > b.copiedAt }
            return a.id.uuidString < b.id.uuidString
        }
    }
}
