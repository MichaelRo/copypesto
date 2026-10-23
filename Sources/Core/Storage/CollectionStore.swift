// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// Changes to collections on a context, each remembered for Undo as one action (ADR 0008). The analogue of
/// `ClipEditor` for the chip bar and Settings → Collections: save through `saveOrRollback`, then record what moved.
public struct CollectionStore {
    private let context: ModelContext
    private let undoHistory: UndoHistory?

    public init(context: ModelContext, undoHistory: UndoHistory?) {
        self.context = context
        self.undoHistory = undoHistory
    }

    /// Applies `change` to collections already in the context and saves. Only collections that differ afterwards are
    /// remembered.
    public func edit(_ kind: CollectionChangeKind, _ boards: [Pinboard], _ change: () -> Void) throws {
        let before = Dictionary(boards.map { ($0.id, PinboardSnapshot($0)) }, uniquingKeysWith: { first, _ in first })
        change()
        try context.saveOrRollback()
        record(kind, boards.compactMap { board in
            let now = PinboardSnapshot(board)
            guard let was = before[board.id], was != now else { return nil }
            return CollectionChange(id: board.id, before: was, after: now)
        })
    }

    /// Inserts new collections and saves.
    public func insert(_ kind: CollectionChangeKind, _ boards: [Pinboard]) throws {
        boards.forEach { context.insert($0) }
        try context.saveOrRollback()
        record(kind, boards.map { CollectionChange(id: $0.id, before: nil, after: PinboardSnapshot($0)) })
    }

    private func record(_ kind: CollectionChangeKind, _ changes: [CollectionChange]) {
        guard let undoHistory, !changes.isEmpty else { return }
        undoHistory.record(UndoEntry(.collectionsChanged(kind, changes)))
    }
}
