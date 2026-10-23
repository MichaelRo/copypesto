// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

extension GridView {
    struct Filtered {
        var items: [ClipboardItem] = []
        var ids: [UUID] = []
    }

    /// Runs the filter and returns the result. Called from `onChange(of: filterKey)`, so the work is decoupled from
    /// body,
    /// which fires on every hover and focus event. The typed text, the scope and the chips are decided on the history
    /// index (plain values); only the clips that pass are looked up, and a clip found by meaning is added after the
    /// same scope and chips.
    func computeFiltered() -> Filtered {
        guard let store = appState.historyStore, let index = store.searchIndex() else { return Filtered() }
        let query = appState.searchText.trimmingCharacters(in: .whitespaces)
        let filter = shelfFilter
        var smart: ((UUID) -> Bool)?
        var plainCollection: UUID?
        if let rule = smartCollectionRule {
            smart = { id in store.item(for: id).map(rule) ?? false }
        } else {
            plainCollection = appState.selectedCollectionID.flatMap { id in
                pinboards.contains { $0.id == id } ? id : nil
            }
        }
        var ids = index.matching(
            HistoryCriteria(
                hidesSensitive: filter.hidesSensitive, appBundleIDs: filter.appBundleIDs,
                collectionID: plainCollection, searchActive: filter.searchActive, types: filter.types,
                sources: filter.sources, dateCutoff: filter.dateCutoff, dateBefore: filter.dateBefore,
                sensitiveOnly: filter.sensitiveOnly, remoteOnly: filter.remoteOnly, query: query
            ),
            smartCollection: smart
        )
        var result = ids.compactMap(store.item(for:))
        if !query.isEmpty, !query.hasPrefix("@") {
            let present = Set(ids)
            for item in filter.apply(to: semanticSupplement) where !present.contains(item.id) {
                result.append(item)
                ids.append(item.id)
            }
        }
        let now = Date.now
        result.removeAll { item in
            guard !item.isPinned, let expiry = item.expiresAt, expiry != .distantPast else { return false }
            return expiry <= now
        }
        let validIDs = Set(result.map(\.id))
        ids.removeAll { !validIDs.contains($0) }
        if plainCollection != nil {
            result.sort { a, b in
                let orderA = a.collectionOrder ?? Int.max
                let orderB = b.collectionOrder ?? Int.max
                if orderA != orderB {
                    return orderA < orderB
                }
                return a.timestamp > b.timestamp
            }
            ids = result.map(\.id)
        }
        return Filtered(items: result, ids: ids)
    }

    /// Puts a new result on the shelf, animating when the change is one that animates, and keeps the focus ring and the
    /// selection on clips that are still there.
    func applyFiltered(_ filtered: Filtered, isUpdate: Bool) {
        if isUpdate, ShelfMotion.shouldAnimateChange(from: cachedFilteredIDs, to: filtered.ids) {
            withAnimation(Motion.animation(.snappy(duration: ShelfMotion.change))) {
                cachedFilteredItems = filtered.items
                cachedFilteredIDs = filtered.ids
            }
        } else {
            cachedFilteredItems = filtered.items
            cachedFilteredIDs = filtered.ids
        }
        guard isUpdate else { return }
        focusedIndex = ShelfFocus.resolvedIndex(focusedID: focusedID, previousIndex: focusedIndex, in: filtered.ids)
        // The ring's clip, whether or not the index moved: a filter can change the clip under the same index.
        focusedID = filtered.ids.indices.contains(focusedIndex) ? filtered.ids[focusedIndex] : nil
        selection.prune(keeping: filtered.ids)
    }

    /// When sensitive clips are hidden they stay hidden, except in search mode where the person can opt in to seeing
    /// them with the Hidden chip (a per-session toggle on `AppState.showHiddenNSFW`) or Sensitive-only.
    var shelfFilter: ShelfFilter {
        let allowHidden = appState.isSearchActive && (appState.showHiddenNSFW || appState.searchSensitiveOnly)
        return ShelfFilter(
            hidesSensitive: nsfwMode.hidesFromGrid && !allowHidden,
            appBundleIDs: appState.appChipFilter,
            inCollection: collectionPredicate,
            searchActive: appState.isSearchActive,
            types: appState.searchTypeFilter,
            sources: appState.searchSourceFilter,
            date: appState.searchDateFilter,
            sensitiveOnly: appState.isSearchActive && appState.searchSensitiveOnly,
            remoteOnly: appState.isSearchActive && appState.searchRemoteOnly
        )
    }

    /// The selected smart collection's rule, or nil for a plain collection or none.
    private var smartCollectionRule: ((ClipboardItem) -> Bool)? {
        guard let pid = appState.selectedCollectionID,
              let pinboard = pinboards.first(where: { $0.id == pid }),
              pinboard.isSmart, let data = pinboard.smartPredicateData,
              let ruleSet = try? SmartCollectionPredicate.decodeRuleSet(data),
              SmartCollectionPredicate.canCompileRuleSet(ruleSet) else { return nil }
        return { ruleSet.matches($0) }
    }

    /// The same rule for a clip that came from the semantic search, which is filtered as clips, not as rows.
    private var collectionPredicate: ((ClipboardItem) -> Bool)? {
        guard let pid = appState.selectedCollectionID, pinboards.contains(where: { $0.id == pid }) else { return nil }
        return smartCollectionRule ?? { $0.collectionID == pid }
    }
}
