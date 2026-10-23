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
        appState.selectedCollectionID = ids[next]
    }
}
