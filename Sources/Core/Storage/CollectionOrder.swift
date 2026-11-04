// SPDX-License-Identifier: MIT
import Foundation

/// How a plain collection lists its clips: the ones the person placed by hand first, in that order, then the rest,
/// newest first. The hand order lives in sealed metadata, so it is read once per clip rather than inside the
/// comparison: sorting 1,000 clips read it about 20,000 times and took 8 ms, half a frame.
public enum CollectionOrder {
    private struct Keyed {
        let item: ClipboardItem
        let order: Int
        let timestamp: Date
    }

    public static func sorted(_ items: [ClipboardItem]) -> [ClipboardItem] {
        items
            .map { Keyed(item: $0, order: $0.collectionOrder ?? Int.max, timestamp: $0.timestamp) }
            .sorted { a, b in
                a.order != b.order ? a.order < b.order : a.timestamp > b.timestamp
            }
            .map(\.item)
    }
}
