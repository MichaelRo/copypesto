// SPDX-License-Identifier: MIT
import Foundation
import os
import PestoCore
import SwiftData

/// The set AutoFill inserts from (ADR 0051): written a moment after the history changes and when Pesto leaves the
/// foreground, emptied by Clear History, and removed with its key when the setting is off or there is no history.
extension MobileAppState {
    private static let quickInsertLogger = Logger(subsystem: AppIdentity.logSubsystem, category: "QuickInsert")

    func startQuickInsert(container: ModelContainer) {
        quickInsertObserver = ModelSaveObserver.observeChanges(in: container) { [weak self] _ in
            self?.quickInsertHistoryChanged()
        }
        writeQuickInsert()
    }

    func quickInsertHistoryChanged() {
        guard quickInsert?.isEnabled() == true else { return }
        quickInsertRewrite?.cancel()
        quickInsertRewrite = Task { [weak self] in
            try? await Task.sleep(for: QuickInsertPolicy.rewriteDelay)
            guard !Task.isCancelled else { return }
            self?.writeQuickInsert()
        }
    }

    func quickInsertSettingChanged() {
        if quickInsert?.isEnabled() == true { writeQuickInsert() } else { removeQuickInsert() }
    }

    /// Writes the set now: the current one with the setting on and a history open, otherwise no file and no key. With
    /// the setting off and no file left, the Keychain is not touched at all.
    func writeQuickInsert() {
        quickInsertRewrite?.cancel()
        quickInsertRewrite = nil
        guard let target = quickInsert else { return }
        if historyLock.holdsOutsideSurfaces, target.isEnabled() { return emptyQuickInsert() }
        guard target.isEnabled(), let container = historyContainer else {
            if target.file.exists { removeQuickInsert() }
            return
        }
        do {
            // A context of its own reads what the store holds now; the main context's copy of a clip the storage
            // actor just edited (made secret, say) is merged only a moment after the save.
            let set = try QuickInsertSelection.set(in: ModelContext(container), now: clock())
            try target.file.write(set, with: target.keys.loadOrCreate())
        } catch {
            Self.quickInsertLogger
                .error("The AutoFill set was not written: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Clear History: nothing it removed may stay insertable, so the set is emptied before anything is chosen again.
    func emptyQuickInsert() {
        quickInsertRewrite?.cancel()
        quickInsertRewrite = nil
        guard let target = quickInsert, target.isEnabled() else { return }
        do {
            try target.file.write(.empty, with: target.keys.loadOrCreate())
        } catch {
            Self.quickInsertLogger
                .error("The AutoFill set was not emptied: \(error.localizedDescription, privacy: .public)")
            target.file.remove()
        }
    }

    func removeQuickInsert() {
        guard let target = quickInsert else { return }
        target.file.remove()
        target.keys.remove()
    }
}
