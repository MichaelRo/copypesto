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

    /// A press switches at once. Presses that follow within `ShelfMotion.cycleCoalesce` (a held key repeats every 30
    /// ms, and
    /// a switch costs more than that) are added up and applied as one switch when the window ends, so the shelf lands
    /// on
    /// the right collection without drawing every one it passed.
    func cyclePinboard(forward: Bool) {
        let key = PerfSignposts.shelf.begin("collectionKey")
        pendingCycleSteps += forward ? 1 : -1
        let sinceLast = ContinuousClock.now - lastCycleApplied
        if sinceLast >= ShelfMotion.cycleCoalesce {
            applyPendingCycle()
        } else if cycleTask == nil {
            cycleTask = Task { @MainActor in
                try? await Task.sleep(for: ShelfMotion.cycleCoalesce - sinceLast)
                cycleTask = nil
                applyPendingCycle()
            }
        }
        key.endAfterNextCommit()
    }

    private func applyPendingCycle() {
        let steps = pendingCycleSteps
        pendingCycleSteps = 0
        lastCycleApplied = .now
        let ids: [UUID?] = [nil] + pinboards.map { Optional($0.id) }
        guard steps != 0 else { return }
        let current = ids.firstIndex(where: { $0 == appState.selectedCollectionID }) ?? 0
        let next = ((current + steps) % ids.count + ids.count) % ids.count
        let switching = PerfSignposts.shelf.begin("collectionSwitch")
        defer { switching.endAfterNextCommit() }
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
