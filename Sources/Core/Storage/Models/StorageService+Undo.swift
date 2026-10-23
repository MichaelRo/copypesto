// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// What ⌘Z or ⇧⌘Z just did, for the banner and for VoiceOver.
public struct UndoOutcome: Equatable, Sendable {
    public enum Direction: Sendable { case undone, redone }

    public let label: UndoLabel
    public let direction: Direction

    public init(label: UndoLabel, direction: Direction) {
        self.label = label
        self.direction = direction
    }
}

/// Undo and redo (ADR 0008). Recording happens where the action does (`deleteItems`, `deleteCollection`,
/// `ClipEditor.edit`, the pin and shortcut functions); applying happens here, on the one writer.
extension StorageService {
    func undoSnapshots(of doomed: [ClipboardItem]) -> [ClipSnapshot]? {
        guard UndoPolicy.canHold(doomed) else { return nil }
        return doomed.map { ClipSnapshot(item: $0, linkPreviewFile: linkPreviews.sealedFile(for: $0.id)) }
    }

    /// Undoes the newest action; nil when there is nothing to undo or the thing it acted on is gone.
    @discardableResult
    public func undo() throws -> UndoOutcome? {
        try step(take: undoHistory.takeUndo, undoing: true)
    }

    @discardableResult
    public func redo() throws -> UndoOutcome? {
        try step(take: undoHistory.takeRedo, undoing: false)
    }

    private func step(take: () -> UndoEntry?, undoing: Bool) throws -> UndoOutcome? {
        guard let entry = take() else { return nil }
        let applied: UndoEntry?
        do {
            applied = try apply(entry, undoing: undoing)
        } catch {
            if undoing { undoHistory.pushUndo(entry) } else { undoHistory.pushRedo(entry) }
            throw error
        }
        guard let applied else { return nil }
        if undoing { undoHistory.pushRedo(applied) } else { undoHistory.pushUndo(applied) }
        return UndoOutcome(label: applied.label, direction: undoing ? .undone : .redone)
    }

    /// Applies one entry in the direction asked and returns the entry to keep for the other direction (the same one,
    /// or for an addition the version that now holds what was removed). Nil when the thing it acted on is gone.
    private func apply(_ entry: UndoEntry, undoing: Bool) throws -> UndoEntry? {
        switch entry.kind {
        case let .clipsDeleted(snapshots):
            if undoing {
                try restore(snapshots)
            } else {
                try deleteItems(ids: snapshots.map(\.id), reason: .user, recordsUndo: false)
            }
            return entry
        case let .collectionDeleted(snapshot):
            return try (undoing ? restoreCollection(snapshot) : removeCollection(id: snapshot.id)) ? entry : nil
        case let .clipsEdited(edits):
            return try applyEdits(edits, undoing: undoing) ? entry : nil
        case let .collectionsChanged(_, changes):
            return try applyCollectionChanges(changes, undoing: undoing) ? entry : nil
        case let .clipsAdded(added):
            return try applyAddition(added, undoing: undoing).map { UndoEntry(.clipsAdded($0)) }
        case let .snippetsReplaced(replacements):
            return try applyReplacements(replacements, undoing: undoing) ? entry : nil
        }
    }

    // MARK: Clips

    private func restore(_ snapshots: [ClipSnapshot]) throws {
        let ids = snapshots.map(\.id)
        let hashes = snapshots.map(\.contentHash)
        let present = try Set(modelContext.fetch(FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { ids.contains($0.id) || hashes.contains($0.contentHash) }
        )).flatMap { [$0.id.uuidString, $0.contentHash] })
        var restored: [ClipSnapshot] = []
        for snapshot in snapshots
            where !present.contains(snapshot.id.uuidString) && !present.contains(snapshot.contentHash)
        {
            let item = snapshot.makeItem()
            if let slot = item.pinnedHotkeyIndex, try !clips(holding: slot).isEmpty { item.pinnedHotkeyIndex = nil }
            modelContext.insert(item)
            restored.append(snapshot)
        }
        let restoredIDs = restored.map(\.id)
        try modelContext.fetch(FetchDescriptor<DeletedItemTombstone>(
            predicate: #Predicate { restoredIDs.contains($0.id) }
        )).forEach(modelContext.delete)
        try saveOrRollback()
        PreviewTextCache.shared.clear()
        for snapshot in restored {
            if let file = snapshot.linkPreviewFile { try? linkPreviews.restoreSealedFile(file, for: snapshot.id) }
        }
        var newest = FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        newest.fetchLimit = 1
        if let top = try modelContext.fetch(newest).first, restoredIDs.contains(top.id) {
            mirrorToLastItemFile(top)
        }
    }

    private func clips(holding slot: Int) throws -> [ClipboardItem] {
        try modelContext.fetch(FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.pinnedHotkeyIndex == slot }))
    }

    // MARK: Collections

    /// Deletes a collection and remembers it. Its clips keep their `collectionID`; undo puts the collection back.
    /// Returns false when there is no such collection.
    @discardableResult
    public func deleteCollection(id: UUID) throws -> Bool {
        guard let board = try pinboard(id: id) else { return false }
        let snapshot = PinboardSnapshot(board)
        modelContext.delete(board)
        try saveOrRollback()
        undoHistory.record(UndoEntry(.collectionDeleted(snapshot)))
        return true
    }

    private func removeCollection(id: UUID) throws -> Bool {
        guard let board = try pinboard(id: id) else { return false }
        modelContext.delete(board)
        try saveOrRollback()
        return true
    }

    private func restoreCollection(_ snapshot: PinboardSnapshot) throws -> Bool {
        guard try pinboard(id: snapshot.id) == nil else { return false }
        let names = try modelContext.fetch(FetchDescriptor<Pinboard>()).map(\.name)
        modelContext.insert(snapshot.makeBoard(named: CollectionNaming.uniqueName(snapshot.name, existing: names)))
        try saveOrRollback()
        return true
    }

    private func pinboard(id: UUID) throws -> Pinboard? {
        var descriptor = FetchDescriptor<Pinboard>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    // MARK: Collections changed (recorded by `CollectionStore`)

    private func applyCollectionChanges(_ changes: [CollectionChange], undoing: Bool) throws -> Bool {
        var applied = false
        for change in changes {
            let target = undoing ? change.before : change.after
            let existing = try pinboard(id: change.id)
            switch (existing, target) {
            case (nil, nil):
                continue
            case let (board?, nil):
                modelContext.delete(board)
            case let (nil, snapshot?):
                let names = try modelContext.fetch(FetchDescriptor<Pinboard>()).map(\.name)
                let name = CollectionNaming.uniqueName(snapshot.name, existing: names)
                modelContext.insert(snapshot.makeBoard(named: name))
            case let (board?, snapshot?):
                snapshot.write(to: board)
            }
            applied = true
        }
        if applied { try saveOrRollback() }
        return applied
    }

    // MARK: Additions

    /// Takes an addition back (its clips are removed, with no tombstone) or puts it back, and returns the entry in its
    /// new state. A clip that cannot be held (large, expiring) is never taken back: it could not be redone.
    private func applyAddition(_ added: AddedClips, undoing: Bool) throws -> AddedClips? {
        switch (added.state, undoing) {
        case let (.present(ids), true):
            let doomed = try modelContext.fetch(FetchDescriptor<ClipboardItem>(
                predicate: #Predicate { ids.contains($0.id) }
            ))
            guard !doomed.isEmpty || !added.boards.isEmpty else { return nil }
            let snapshots: [ClipSnapshot]
            if doomed.isEmpty {
                snapshots = []
            } else if let held = undoSnapshots(of: doomed) {
                snapshots = held
            } else {
                return nil
            }
            if !doomed.isEmpty { try deleteItems(ids: doomed.map(\.id), reason: .undone, recordsUndo: false) }
            for board in added.boards {
                _ = try removeCollection(id: board.id)
            }
            return AddedClips(kind: added.kind, snapshots: snapshots, boards: added.boards)
        case let (.absent(snapshots), false):
            for board in added.boards {
                guard try pinboard(id: board.id) == nil else { continue }
                let names = try modelContext.fetch(FetchDescriptor<Pinboard>()).map(\.name)
                modelContext.insert(board.makeBoard(named: CollectionNaming.uniqueName(board.name, existing: names)))
            }
            try restore(snapshots)
            return AddedClips(kind: added.kind, ids: snapshots.map(\.id), boards: added.boards)
        default:
            return nil
        }
    }

    // MARK: Snippets

    /// Remembers a snippet whose text was replaced, from the snapshot taken before the change.
    func recordReplacement(of item: ClipboardItem, before: ClipSnapshot) {
        let after = ClipSnapshot(item: item, linkPreviewFile: nil)
        guard before.isHoldable, after.isHoldable else { return }
        undoHistory.record(UndoEntry(.snippetsReplaced([ClipReplacement(before: before, after: after)])))
    }

    private func applyReplacements(_ replacements: [ClipReplacement], undoing: Bool) throws -> Bool {
        var applied = false
        for replacement in replacements {
            let id = replacement.id
            var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let item = try modelContext.fetch(descriptor).first else { continue }
            (undoing ? replacement.before : replacement.after).writeContent(to: item, in: modelContext)
            lastItemStore.clear(ifItemID: id)
            applied = true
        }
        if applied {
            try saveOrRollback()
            PreviewTextCache.shared.clear()
        }
        return applied
    }

    // MARK: Edits

    /// Remembers edits a caller already made, from the state each clip was in before. Nothing is recorded for a clip
    /// that did not change.
    func recordEdits(_ before: [(item: ClipboardItem, state: ClipFieldState)]) {
        let edits = before.compactMap {
            ClipEdit(id: $0.item.id, before: $0.state, after: ClipFieldState($0.item))
        }
        if !edits.isEmpty { undoHistory.record(UndoEntry(.clipsEdited(edits))) }
    }

    private func applyEdits(_ edits: [ClipEdit], undoing: Bool) throws -> Bool {
        var applied = false
        for edit in edits {
            let id = edit.id
            var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let item = try modelContext.fetch(descriptor).first else { continue }
            try write(undoing ? edit.before : edit.after, fields: edit.fields, to: item)
            applied = true
        }
        if applied { try saveOrRollback() }
        return applied
    }

    private func writeMetadata(_ state: ClipFieldState, fields: Set<ClipField>, to item: ClipboardItem) {
        guard !fields.isDisjoint(with: [.title, .note, .tags, .icon, .order]) else { return }
        item.updateMetadata { metadata in
            if fields.contains(.title) { metadata.customTitle = state.customTitle }
            if fields.contains(.note) { metadata.userNote = state.userNote }
            if fields.contains(.tags) { metadata.tags = state.tags }
            if fields.contains(.icon) { metadata.customSymbolName = state.customSymbolName }
            if fields.contains(.order) { metadata.collectionOrder = state.collectionOrder }
        }
    }

    private func write(_ state: ClipFieldState, fields: Set<ClipField>, to item: ClipboardItem) throws {
        writeMetadata(state, fields: fields, to: item)
        if fields.contains(.collection) { item.collectionID = state.collectionID }
        if fields.contains(.pinned) { item.isPinned = state.isPinned }
        if fields.contains(.shortcut) {
            if let slot = state.pinnedHotkeyIndex {
                for other in try clips(holding: slot) where other.id != item.id {
                    other.pinnedHotkeyIndex = nil
                }
            }
            item.pinnedHotkeyIndex = state.pinnedHotkeyIndex
        }
        if fields.contains(.sensitive) { item.isNSFW = state.isNSFW }
        if fields.contains(.expiry) { item.expiresAt = state.expiresAt }
    }
}
