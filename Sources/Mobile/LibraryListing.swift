// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// The ids the grid draws, worked out when one of the things that decide them changes, never in a view's body: a
/// focus move or the minute tick draws the cards again and lists nothing.
@MainActor
enum LibraryListing {
    struct Key: Equatable {
        var revision: Int
        var query: String
        var filter: LibraryFilter
        var isSearching: Bool
        var orderVersion: Int
        var textEdits: Int
        var byMeaning: [UUID]
        var hidesSensitive: Bool
        var smartRule: Data?
    }

    struct Result: Equatable {
        var ids: [UUID]
        var animates: Bool
    }

    static func list(
        _ key: Key, in store: HistoryStore, order: GridOrder, smartRule: ((UUID) -> Bool)?, now: Date = .now
    )
    -> Result {
        guard let index = store.searchIndex() else { return Result(ids: [], animates: false) }
        let kind = key.isSearching ? key.filter.kind : nil
        let cutoff = key.isSearching ? key.filter.dateCutoff(now: now) : nil
        let remote = key.isSearching && key.filter.otherDevicesOnly
        func ids(query: String) -> [UUID] {
            key.filter.scope.ids(
                in: index, query: query, kind: kind, smartRule: smartRule, hidesSensitive: key.hidesSensitive,
                dateCutoff: cutoff, otherDevicesOnly: remote, now: now
            )
        }
        let context = "\(key.filter.scope)|\(key.query)|\(kind?.rawValue ?? "")|\(cutoff != nil)|\(remote)"
        let arranged = order.arrange(ids(query: key.query), context: context)
        var result = arranged
        if !key.byMeaning.isEmpty, SemanticSearch.asksForMeaning(key.query) {
            result = SemanticSearch.merged(
                textMatches: arranged, byMeaning: key.byMeaning, allowed: Set(ids(query: ""))
            )
        }
        return Result(ids: result, animates: order.shouldAnimate(to: result))
    }
}
