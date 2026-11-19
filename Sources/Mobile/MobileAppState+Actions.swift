// SPDX-License-Identifier: MIT
import Foundation
import os
import PestoCore
import SwiftData

/// What the library does to clips. Every change goes through Core's one path for it, so it is saved with a rollback,
/// remembered for Undo where ADR 0008 says so, and reported when it fails.
extension MobileAppState {
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "MobileLibrary")

    var undoHistory: UndoHistory? {
        storageService?.undoHistory
    }

    func clipEditor(context: ModelContext) -> ClipEditor {
        ClipEditor(
            context: context, historyStore: historyStore, report: { [self] in report($0, $1) }, didEdit: {},
            undoHistory: undoHistory
        )
    }

    func collectionStore(context: ModelContext) -> CollectionStore {
        CollectionStore(context: context, undoHistory: undoHistory)
    }

    func report(_ failure: String.LocalizationValue, _ body: () throws -> Void) {
        do {
            try body()
        } catch {
            Self.logger.error("Library action failed: \(error.localizedDescription, privacy: .public)")
            tell(String(localized: failure), isProblem: true)
        }
    }

    func reportAsync(_ failure: String.LocalizationValue, _ body: () async throws -> Void) async {
        do {
            try await body()
        } catch {
            Self.logger.error("Library action failed: \(error.localizedDescription, privacy: .public)")
            tell(String(localized: failure), isProblem: true)
        }
    }

    func tell(_ text: String, isProblem: Bool = false) {
        notice = Notice(text: text, isProblem: isProblem)
        noticeDismissal?.cancel()
        noticeDismissal = Task { [weak self] in
            try? await Task.sleep(for: Self.noticeDuration)
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    /// Adds what the person handed Pesto. A copy over the size limit is refused by ingest, and the refusal is shown.
    @discardableResult
    func add(_ capture: PasteboardCapture?) async -> Bool {
        guard let service = storageService else { return false }
        guard let capture else {
            tell(String(localized: "There was nothing Pesto can keep."), isProblem: true)
            return false
        }
        do {
            try await service.ingest(capture)
            return true
        } catch let refusal as ClipSizePolicy.TooLarge {
            tell(refusal.message, isProblem: true)
        } catch {
            Self.logger.error("Adding a clip failed: \(error.localizedDescription, privacy: .public)")
            tell(String(localized: "Couldn\u{2019}t add the clip."), isProblem: true)
        }
        return false
    }

    /// What the Paste button or a drop delivered.
    func add(from providers: [NSItemProvider], method: CaptureMethod, pasteboardTypes: [String] = []) async {
        guard !ItemProviderCapture.isConcealed(providers, pasteboardTypes: pasteboardTypes) else { return }
        do {
            try await add(
                ItemProviderCapture.capture(from: providers, pasteboardTypes: pasteboardTypes)?
                    .with(captureMethod: method)
            )
        } catch {
            Self.logger.error("Reading a paste or drop failed: \(error.localizedDescription, privacy: .public)")
            tell(String(localized: "Couldn\u{2019}t read what was pasted."), isProblem: true)
        }
    }

    func delete(_ ids: [UUID]) async {
        guard let service = storageService, !ids.isEmpty else { return }
        let mark = service.undoHistory.recordedCount
        await reportAsync("Couldn\u{2019}t delete the clip.") {
            try await service.deleteItems(ids: ids, reason: .user)
            ids.forEach(secretReveal.hide)
            offerUndo(since: mark)
            // A deleted clip leaves the widget and AutoFill at once, not after the rewrite's pause.
            writeQuickInsert()
            await writeWidget()
        }
    }

    func offerUndo(since recordedCount: Int) {
        guard let history = undoHistory, history.recordedCount > recordedCount,
              let label = history.undoLabel else { return }
        undoOffer = label
        undoOfferDismissal?.cancel()
        undoOfferDismissal = Task { [weak self] in
            try? await Task.sleep(for: Self.undoOfferDuration)
            guard !Task.isCancelled else { return }
            self?.undoOffer = nil
        }
    }

    func dismissUndoOffer() {
        undoOfferDismissal?.cancel()
        undoOfferDismissal = nil
        undoOffer = nil
    }

    func undo() async {
        guard let service = storageService else { return }
        dismissUndoOffer()
        await reportAsync("Couldn\u{2019}t undo.") {
            try await service.undo()
        }
    }

    func togglePin(_ id: UUID) async {
        guard let service = storageService else { return }
        var pinned = false
        await reportAsync("Couldn\u{2019}t save the change.") {
            pinned = try await service.togglePinned(id: id) == true
        }
        if pinned { clipWasKept() }
    }

    /// Copies the clip's real content (a secret too, without showing it) and moves the clip to the front, as a copy
    /// from the Mac's shelf does. A secret stays on this device and leaves the clipboard after two minutes.
    @discardableResult
    func copy(_ item: ClipboardItem) -> Bool {
        guard let content = ClipContent.of(item) else {
            tell(String(localized: "Couldn\u{2019}t open the clip."), isProblem: true)
            return false
        }
        if let text = content.plainText, let request = SnippetFillRequest.make(for: item, text: text, at: clock()) {
            switch request {
            case let .ask(request):
                pendingFill = request
                return false
            case let .copy(expanded):
                return finishCopy(item, content: .text(expanded))
            }
        }
        return finishCopy(item, content: content)
    }

    func finishCopy(_ item: ClipboardItem, content: ClipContent) -> Bool {
        MobileClipboard.write(content, protected: item.sensitivityRaw != nil)
        var saved = true
        if let context = item.modelContext {
            item.bringToFront(at: clock())
            saved = false
            report("Couldn\u{2019}t save the change.") {
                try saveChanges(context)
                saved = true
            }
        }
        if saved { tell(String(localized: "Copied")) }
        return true
    }

    func moveToCollection(_ item: ClipboardItem, collectionID: UUID?) {
        guard let context = item.modelContext else { return }
        clipEditor(context: context).edit(item) { $0.collectionID = collectionID }
    }

    func addCollection(named name: String, existing: [Pinboard]) -> Pinboard? {
        var draft = CollectionDraft.new(existing: existing)
        draft.name = name
        return addCollection(draft, existing: existing)
    }

    func addCollection(_ draft: CollectionDraft, existing: [Pinboard]) -> Pinboard? {
        guard let context = historyContainer?.mainContext else { return nil }
        let name = draft.trimmedName
        var added: Pinboard?
        report("Couldn\u{2019}t add the collection.") {
            let board = try Pinboard(
                name: CollectionNaming.uniqueName(
                    name.isEmpty ? CollectionNaming.defaultName : name, existing: existing.map(\.name)
                ),
                symbolName: draft.symbol,
                colorHex: draft.colorHex,
                sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1,
                isSmart: draft.isSmart,
                smartPredicateData: draft.isSmart ? draft.rules?.encoded() : nil
            )
            try collectionStore(context: context).insert(.create, [board])
            added = board
        }
        return added
    }

    func renameCollection(_ board: Pinboard, to name: String, existing: [Pinboard]) {
        var draft = CollectionDraft(board)
        draft.name = name
        updateCollection(board, to: draft, existing: existing)
    }

    /// Name, icon and color in one change, which one Undo takes back.
    func updateCollection(_ board: Pinboard, to draft: CollectionDraft, existing: [Pinboard]) {
        guard let context = board.modelContext, draft.differs(from: board) else { return }
        let name = draft.trimmedName
        let others = existing.filter { $0.id != board.id }.map(\.name)
        let unique = name.isEmpty || name == board.name ? board.name : CollectionNaming.uniqueName(
            name,
            existing: others
        )
        report("Couldn\u{2019}t save the collection.") {
            let rules = try board.isSmart && draft.isSmart && draft.rulesDiffer(from: board) ? draft.rules?
                .encoded() : nil
            try collectionStore(context: context).edit(.edit, [board]) {
                board.name = unique
                board.symbolName = draft.symbol
                board.colorHex = draft.colorHex
                if let rules { board.smartPredicateData = rules }
            }
        }
    }

    func deleteCollection(_ id: UUID) async {
        guard let service = storageService else { return }
        let mark = service.undoHistory.recordedCount
        await reportAsync("Couldn\u{2019}t delete the collection.") {
            try await service.deleteCollection(id: id)
            offerUndo(since: mark)
        }
    }

    func nonPinnedCount() async -> Int {
        guard let service = storageService else { return 0 }
        return await (try? service.nonPinnedCount(in: .all)) ?? 0
    }

    /// Clear History: every clip that is not pinned, for good. `clearNonPinned` also empties Undo (ADR 0008).
    func clearHistory() async {
        guard let service = storageService else { return }
        dismissUndoOffer()
        ShareFile.removeAll()
        secretReveal.hideAll()
        decodedJWT = nil
        closeAI()
        await reportAsync("Couldn\u{2019}t clear the history.") {
            let ids = try await service.clearNonPinned(in: .all)
            emptyQuickInsert()
            lastWidgetSnapshot = nil
            await emptyWidget()
            ThumbnailCache.shared.clear()
            tell(String(localized: "Cleared \(ids.count) clips."))
        }
    }

    /// Pesto left the foreground: whatever was shown hides again (ADR 0003), and the AutoFill set and the widget's
    /// snapshot are brought up to date before iOS may suspend the app (ADR 0051, ADR 0052).
    func didLeaveForeground() {
        isActivated = false
        historyLock.didLeaveForeground(at: clock())
        closeAI()
        ShareFile.removeAll()
        secretReveal.hideAll()
        decodedJWT = nil
        writeQuickInsert()
        let hold = backgroundWork.hold("Widget snapshot")
        Task {
            await refreshWidgetPresence()
            hold.finish()
        }
    }
}
