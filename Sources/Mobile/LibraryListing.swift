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
        var indexByID: [UUID: Int]

        init(ids: [UUID], animates: Bool, indexByID: [UUID: Int]? = nil) {
            self.ids = ids
            self.animates = animates
            self.indexByID = indexByID
                ?? Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }

    static func list(
        _ key: Key, in store: HistoryStore, order: GridOrder, smartRule: ((UUID) -> Bool)?, now: Date = .now
    )
    -> Result {
        guard let index = store.searchIndex() else { return Result(ids: [], animates: false) }
        let kinds = key.isSearching ? key.filter.kinds : []
        let window = key.isSearching ? key.filter.dateWindow(now: now) : (cutoff: nil, before: nil)
        let sourceBundleID = key.isSearching ? key.filter.sourceBundleID : nil
        let sensitive = key.isSearching && key.filter.sensitiveOnly
        let remote = key.isSearching && key.filter.otherDevicesOnly
        func ids(query: String) -> [UUID] {
            key.filter.scope.ids(
                in: index, query: query, kinds: kinds, smartRule: smartRule, hidesSensitive: key.hidesSensitive,
                dateCutoff: window.cutoff, dateBefore: window.before, sourceBundleID: sourceBundleID,
                sensitiveOnly: sensitive, otherDevicesOnly: remote, now: now
            )
        }
        let kindNames = kinds.map(\.rawValue).sorted().joined(separator: ",")
        let bounds = "\(window.cutoff != nil)|\(window.before != nil)"
        let context =
            "\(key.filter.scope)|\(key.query)|\(kindNames)|\(bounds)|\(sourceBundleID ?? "")|\(sensitive)|\(remote)"
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
