// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftData

/// ⌘Z, ⇧⌘Z and the banner that offers an undo after a delete (ADR 0008). What can be undone lives in
/// `StorageService.undoHistory`; this applies it and tells the person.
extension AppState {
    var undoHistory: UndoHistory? {
        storageService?.undoHistory
    }

    /// Shows "Deleted 3 clips · Undo" when the stack kept an action after `recordedCount` (a delete that cannot be
    /// undone offers nothing).
    func offerUndo(since recordedCount: Int) {
        guard let history = undoHistory, history.recordedCount > recordedCount,
              let label = history.undoLabel else { return }
        undoOffer = label
        Announcer.announce("\(UndoText.action(label)). Command Z to undo.", priority: .high)
        scheduleUndoOfferDismissal(after: Self.defaultUserMessageDuration)
    }

    private func scheduleUndoOfferDismissal(after duration: Duration) {
        undoOfferDismissal?.cancel()
        undoOfferDismissal = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.undoOffer = nil
        }
    }

    /// The pointer is on the banner: it stays while it is being read.
    func holdUndoOffer() {
        undoOfferDismissal?.cancel()
        undoOfferDismissal = nil
    }

    /// The pointer left: the banner goes after a short grace, not at once.
    func releaseUndoOffer(after grace: Duration = .seconds(4)) {
        guard undoOffer != nil else { return }
        scheduleUndoOfferDismissal(after: grace)
    }

    /// Deletes a collection through the service, which remembers it. `fromShelf` offers the banner.
    func deleteCollection(id: UUID, fromShelf: Bool) {
        if selectedCollectionID == id { selectedCollectionID = nil }
        guard let service = storageService else { return }
        let mark = service.undoHistory.recordedCount
        Task {
            await attempt("Couldn\u{2019}t delete the collection") {
                try await service.deleteCollection(id: id)
                if fromShelf { offerUndo(since: mark) }
            }
        }
    }

    /// The one way a view edits a clip outside the shelf's grid: saved, reported on failure and remembered for Undo.
    func clipEditor(context: ModelContext, didEdit: @escaping () -> Void = {}) -> ClipEditor {
        ClipEditor(
            context: context, historyStore: historyStore, report: { [self] in attempt($0, $1) }, didEdit: didEdit,
            undoHistory: undoHistory
        )
    }

    /// The one way a view changes collections: saved and remembered for Undo.
    func collectionStore(context: ModelContext) -> CollectionStore {
        CollectionStore(context: context, undoHistory: undoHistory)
    }

    func dismissUndoOffer() {
        undoOfferDismissal?.cancel()
        undoOfferDismissal = nil
        if undoOffer != nil { undoOffer = nil }
    }

    func performUndo() {
        run(redo: false)
    }

    func performRedo() {
        run(redo: true)
    }

    private func run(redo: Bool) {
        guard let service = storageService, !isHistoryLockedNow() else { return }
        dismissUndoOffer()
        Task {
            await attempt(redo ? "Couldn\u{2019}t redo" : "Couldn\u{2019}t undo") {
                guard let outcome = try await (redo ? service.redo() : service.undo()) else { return }
                undoGeneration += 1
                dropSelectedCollectionIfGone()
                Announcer.announce(UndoText.done(outcome), priority: .high)
            }
        }
    }

    /// Undoing the creation of the collection that is showing (or redoing its delete) leaves nothing to show.
    private func dropSelectedCollectionIfGone() {
        guard let id = selectedCollectionID, let container = historyContainer else { return }
        var descriptor = FetchDescriptor<Pinboard>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if (try? container.mainContext.fetch(descriptor))?.isEmpty == true { selectedCollectionID = nil }
    }
}
