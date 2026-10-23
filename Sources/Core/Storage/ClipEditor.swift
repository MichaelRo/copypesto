// SPDX-License-Identifier: MIT
import Foundation
import os
import SwiftData

/// An edit to a clip, done the one way the history is edited: change it, save with a rollback when the save fails (a
/// failed save left pending would ride along with the next unrelated one, ADR 0007), tell the person what failed, keep
/// the search row in step with the clip, and tell the shelf that what it filters on may have moved. The card and the
/// shelf used to spell that sequence out in a dozen places, three of them forgetting the rollback's message.
@MainActor
public struct ClipEditor {
    private let context: ModelContext
    private let historyStore: HistoryStore?
    private let report: (String.LocalizationValue, () throws -> Void) -> Void
    private let didEdit: () -> Void
    private let undoHistory: UndoHistory?
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "ClipEditor")

    /// - Parameters:
    ///   - report: runs a throwing step and shows the person the failure (`AppState.attempt`).
    ///   - didEdit: called after an edit that can change what a filter shows.
    public init(
        context: ModelContext,
        historyStore: HistoryStore?,
        report: @escaping (String.LocalizationValue, () throws -> Void) -> Void,
        didEdit: @escaping () -> Void,
        undoHistory: UndoHistory? = nil
    ) {
        self.context = context
        self.historyStore = historyStore
        self.report = report
        self.didEdit = didEdit
        self.undoHistory = undoHistory
    }

    /// Applies `change` to `item` and saves it. `refreshesRow` keeps the search text of the clip current;
    /// `changesFilter`
    /// tells the shelf to filter again.
    public func edit(
        _ item: ClipboardItem, refreshesRow: Bool = true, changesFilter: Bool = true, _ change: (ClipboardItem) -> Void
    ) {
        let before = undoHistory == nil ? nil : ClipFieldState(item)
        change(item)
        var saved = false
        report("Couldn\u{2019}t save the change") {
            try context.saveOrRollback()
            saved = true
        }
        if saved, let before, let edit = ClipEdit(id: item.id, before: before, after: ClipFieldState(item)) {
            undoHistory?.record(UndoEntry(.clipsEdited([edit])))
        }
        if refreshesRow { historyStore?.refreshRow(for: item) }
        if changesFilter { didEdit() }
    }

    /// A change the app derived rather than the person made (a fetched link preview, a content flag): saved the same
    /// way, with the rollback, but not remembered for Undo. A failed save is logged, and the person is told only when
    /// `reportsFailure` (the flag that blurs a card is a protection, a page title is not).
    public func applyDerived(
        to item: ClipboardItem, changesFilter: Bool = false, reportsFailure: Bool = false,
        _ change: (ClipboardItem) -> Void
    ) {
        change(item)
        do {
            try context.saveOrRollback()
        } catch {
            Self.logger.error("A derived change was not saved: \(error.localizedDescription, privacy: .public)")
            if reportsFailure { report("Couldn\u{2019}t save the change") { throw error } }
        }
        historyStore?.refreshRow(for: item)
        if changesFilter { didEdit() }
    }

    /// One edit to several clips (a card dragged to a new place), saved once and remembered as one action.
    public func edit(
        _ items: [ClipboardItem], refreshesRow: Bool = true, changesFilter: Bool = true,
        _ change: (ClipboardItem) -> Void
    ) {
        let before = undoHistory == nil ? [] : items.map { ClipFieldState($0) }
        items.forEach(change)
        var saved = false
        report("Couldn\u{2019}t save the change") {
            try context.saveOrRollback()
            saved = true
        }
        if saved, undoHistory != nil {
            let edits = zip(items, before).compactMap { ClipEdit(id: $0.id, before: $1, after: ClipFieldState($0)) }
            if !edits.isEmpty { undoHistory?.record(UndoEntry(.clipsEdited(edits))) }
        }
        if refreshesRow { items.forEach { historyStore?.refreshRow(for: $0) } }
        if changesFilter { didEdit() }
    }

    /// For an edit that was already saved by the caller (a tag added, a note typed in a popover that saves itself).
    public func refresh(_ item: ClipboardItem) {
        historyStore?.refreshRow(for: item)
        didEdit()
    }
}
