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

    // MARK: - Delete

    /// The Delete key: the selection, or the focused clip.
    func requestDeleteForKey() {
        let focused = displayedItems.indices.contains(focusedIndex) ? displayedItems[focusedIndex].id : nil
        let targets = ShelfDeletion.targets(
            selection: selection.ordered(in: cachedFilteredIDs), focused: focused
        )
        if !targets.isEmpty { pendingDelete = targets }
    }

    /// A card's own Delete: the selection when the card is part of one, otherwise that card.
    func requestDelete(ofCard id: UUID) {
        pendingDelete = ShelfDeletion.targets(
            selection: selection.ordered(in: cachedFilteredIDs), requestedFor: id
        )
    }

    /// How many of these clips ⌘Z can bring back: excludes large, expiring, credential, or pending items.
    func undoableDeletionCount(_ ids: [UUID]) -> Int {
        let wanted = Set(ids)
        return UndoPolicy.holdable(cachedFilteredItems.filter { wanted.contains($0.id) }).count
    }

    func confirmDelete() {
        guard let ids = pendingDelete else { return }
        pendingDelete = nil
        deleteSelected(ids)
    }

    func deleteSelected(_ ids: [UUID]) {
        guard !appState.isHistoryLockedNow() else { return }
        let mark = appState.undoHistory?.recordedCount ?? 0
        Task {
            await appState.attempt("Couldn’t delete the selected clips") {
                if let count = try await appState.storageService?.deleteItems(ids: ids, reason: .user) {
                    AutoBackupSettings().lowerBaseline(by: count)
                    appState.offerUndo(since: mark)
                }
            }
        }
        selection.clear()
    }

    // MARK: - Paste One by One

    func pasteSelectedOneByOne() {
        let (chosen, leftOut) = PasteStack.limited(selectedItems, byteSize: \.byteSize)
        if leftOut > 0 {
            appState.showUserMessage(
                "Paste One by One takes \(CountText.clips(PasteStack.maxItems)) or 50 MB. The first ones are in it."
            )
        }
        let stackItems = chosen.map { PasteStack.Item(clip: $0) }

        guard stackItems.count > 1 else { return }

        let sources = chosen.map {
            StackSnippetSource(id: $0.id, isSnippet: $0.isTemplate, remembered: $0.metadata.fieldMemory ?? [:])
        }
        Task {
            if !appState.isOverlayVisible {
                appState.pasteCoordinator.focusRestoration.capture()
            }
            guard let ready = await appState.expandedStackItems(stackItems, sources: sources) else { return }
            let stack = PasteStack(items: ready)
            selection.clear()

            // Activate the stack — AppDelegate's overlay-hidden handler will paste item 1.
            appState.activeStack = stack
            appState.close(.startStack)
        }
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

    /// Placeholders during quick switches (`SwitchQualityPolicy`). Off with VoiceOver, which would hear nothing while
    /// the
    /// row is light, and in a UI-test launch, whose tests read the cards a moment after a key, unless a benchmark is
    /// recording; `alwaysFull` is the benchmark's way to compare.
    private var adaptsSwitchQuality: Bool {
        let configuration = RuntimeConfiguration.current
        let allowed = configuration.mode != .uiTest || configuration.recordsPerfTimeline
        return allowed && !NSWorkspace.shared.isVoiceOverEnabled && !ShelfExperiments.shared.isOn("alwaysFull")
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
        let quality = adaptsSwitchQuality ? switchPolicy.quality(at: .now) : .full
        detail.isLight = quality == .light
        settleTask?.cancel()
        let started = ContinuousClock.now
        CommitClock.afterNextCommit(from: started) { millis in switchPolicy.committed(quality, millis: millis) }
        if quality == .light {
            settleTask = Task { @MainActor in
                try? await Task.sleep(for: switchPolicy.settle)
                guard !Task.isCancelled else { return }
                withAnimation(Motion.animation(.pestoQuick)) { detail.isLight = false }
            }
        }
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
