// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

extension GridView {
    // MARK: - Selection action bar

    var selectedItems: [ClipboardItem] {
        let byID = Dictionary(cachedFilteredItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return selection.ordered(in: cachedFilteredIDs).compactMap { byID[$0] }
    }

    var canPasteAll: Bool {
        selectedItems.count > 1 && selectedItems.allSatisfy { $0.type == .text || $0.type == .code }
    }

    var actionBar: some View {
        SelectionActionBar(
            count: selection.count,
            canPasteAll: canPasteAll,
            onPasteAll: pasteAllSelected,
            onPasteOneByOne: pasteSelectedOneByOne,
            onDelete: { pendingDelete = selectedItems.map(\.id) }
        )
    }

    // MARK: - Pinboard cycling (⌘[ / ⌘])

    func cyclePinboard(forward: Bool) {
        let ids: [UUID?] = [nil] + pinboards.map { Optional($0.id) }
        guard !ids.isEmpty else { return }
        let current = ids.firstIndex(where: { $0 == appState.selectedCollectionID }) ?? 0
        let next = forward
            ? (current + 1) % ids.count
            : (current - 1 + ids.count) % ids.count
        // Filtered here, in the same step as the switch: left to `onChange` the first frame built the new row from the
        // previous collection's clips and the right ones replaced them a frame later.
        appState.selectedCollectionID = ids[next]
        displayLimit = 1000
        let filtering = PerfSignposts.shelf.begin("collectionFilter")
        let filtered = computeFiltered()
        filtering.end()
        let applying = PerfSignposts.shelf.begin("collectionApply")
        applyFiltered(filtered, isUpdate: true)
        applying.end()
        appliedFilterKey = filterKey
    }
}
