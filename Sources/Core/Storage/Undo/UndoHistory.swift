// SPDX-License-Identifier: MIT
import Foundation
import Synchronization

/// The stack behind ⌘Z and ⇧⌘Z (ADR 0008). It lives in memory only and holds sealed bytes, never plaintext; every
/// path that wipes history empties it (`clear()`), and it forgets the oldest entry before it passes its budget.
/// Applying an entry is `StorageService.undo()` and `redo()`; this type only keeps the order.
public final class UndoHistory: Sendable {
    private struct State {
        var undo: [UndoEntry] = []
        var redo: [UndoEntry] = []
        var recorded = 0
    }

    private let state = Mutex(State())
    private let maxEntries: Int
    private let maxHeldBytes: Int

    public init(maxEntries: Int = UndoPolicy.maxEntries, maxHeldBytes: Int = UndoPolicy.maxHeldBytes) {
        self.maxEntries = maxEntries
        self.maxHeldBytes = maxHeldBytes
    }

    /// Adds a new action, which ends any redo. An entry larger than the whole budget is not kept: returns false.
    @discardableResult
    public func record(_ entry: UndoEntry) -> Bool {
        guard entry.heldBytes <= maxHeldBytes else { return false }
        state.withLock {
            $0.redo.removeAll()
            $0.undo.append(entry)
            $0.recorded += 1
            trim(&$0)
        }
        return true
    }

    public func clear() {
        state.withLock {
            $0.undo.removeAll()
            $0.redo.removeAll()
        }
    }

    public var undoLabel: UndoLabel? {
        state.withLock { $0.undo.last?.label }
    }

    public var redoLabel: UndoLabel? {
        state.withLock { $0.redo.last?.label }
    }

    /// How many actions have been recorded in all, so a caller can tell whether its own action was kept.
    public var recordedCount: Int {
        state.withLock { $0.recorded }
    }

    public var heldBytes: Int {
        state.withLock { ($0.undo + $0.redo).reduce(0) { $0 + $1.heldBytes } }
    }

    public var entryCount: Int {
        state.withLock { $0.undo.count + $0.redo.count }
    }

    func takeUndo() -> UndoEntry? {
        state.withLock { $0.undo.popLast() }
    }

    func takeRedo() -> UndoEntry? {
        state.withLock { $0.redo.popLast() }
    }

    /// After an undo was applied the entry waits to be redone; after a redo it waits to be undone again.
    func pushRedo(_ entry: UndoEntry) {
        state.withLock {
            $0.redo.append(entry)
            trim(&$0)
        }
    }

    func pushUndo(_ entry: UndoEntry) {
        state.withLock {
            $0.undo.append(entry)
            trim(&$0)
        }
    }

    private func trim(_ state: inout State) {
        while state.undo.count + state.redo.count > maxEntries || total(state) > maxHeldBytes {
            if !state.redo.isEmpty {
                state.redo.removeFirst()
            } else if !state.undo.isEmpty {
                state.undo.removeFirst()
            } else {
                break
            }
        }
    }

    private func total(_ state: State) -> Int {
        (state.undo + state.redo).reduce(0) { $0 + $1.heldBytes }
    }
}
