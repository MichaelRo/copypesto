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
            .map { Keyed(item: $0, order: $0.collectionOrder ?? Int.max, copiedAt: $0.copiedAt) }
            .sorted { a, b in
                a.order != b.order ? a.order < b.order : a.copiedAt > b.copiedAt
            }
            .map(\.item)
    }
}
