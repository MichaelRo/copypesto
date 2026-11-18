// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// What the History Lock does to the app (ADR 0054), as the Mac's `AppState.lockHistory` does: nothing decrypted
/// stays in memory, Undo forgets, Shortcuts find nothing, sync pauses, and what was shared or tapped on a widget
/// waits for the unlock. With the lock on, the widget and the AutoFill set hold nothing at all, because iOS gives
/// Pesto no moment to empty them when the timeout passes while it is away.
extension MobileAppState {
    var isHistoryLocked: Bool {
        historyLock.isLocked
    }

    /// Asks the lock first, so a Shortcut run while Pesto is away past the timeout finds it locked.
    func isHistoryLockedNow() -> Bool {
        if historyLock.lockIfAwayTooLong(at: clock()) { forgetUnlockedState() }
        return historyLock.isLocked
    }

    func lockDidBecomeActive() {
        _ = isHistoryLockedNow()
        historyLock.didBecomeActive()
    }

    func lockHistory() {
        guard historyLock.isEnabled else { return }
        historyLock.lock()
        forgetUnlockedState()
    }

    @discardableResult
    func unlockHistory() async -> Bool {
        guard await historyLock.unlock() else { return false }
        didUnlock()
        return true
    }

    /// Where nothing can authenticate the lock protects no one, so the lock screen offers to turn it off (the Mac's
    /// `HistoryLockPolicy.permitsTurningLockOff`).
    func turnOffHistoryLock() async -> Bool {
        guard await HistoryLockPolicy.permitsTurningLockOff(
            using: historyLock.authenticator, reason: String(localized: "Turn off the history lock"),
            grace: historyLock.grace
        ) else { return false }
        AppDefaults.store.set(false, for: Setting.biometricLockEnabled)
        historyLockSettingChanged()
        return true
    }

    func historyLockSettingChanged() {
        if historyLock.isEnabled {
            HistoryLockPolicy.lockWasSwitchedOn()
            if historyLock.holdsOutsideSurfaces { emptyOutsideSurfaces() }
        } else {
            let wasLocked = historyLock.isLocked
            historyLock.lockWasTurnedOff()
            if wasLocked { didUnlock() } else { writeOutsideSurfaces() }
        }
    }

    private func forgetUnlockedState() {
        secretReveal.hideAll()
        storageService?.undoHistory.clear()
        undoOfferDismissal?.cancel()
        undoOffer = nil
        clipboardOfferCount = nil
        pendingFill = nil
        linkedClip = nil
        historyStore?.setVisible(false)
        historyStore?.dropSearchText()
        PreviewTextCache.shared.clear()
        emptyOutsideSurfaces()
    }

    private func didUnlock() {
        historyStore?.setVisible(true)
        syncDidBecomeActive()
        inboxDidBecomeActive()
        Task { await clipboardDidBecomeActive() }
        if let link = heldLink {
            heldLink = nil
            open(link)
        }
    }

    /// The toggle under the lock row: with it on the widget and the set are written as without the lock, with it off
    /// they go back to saying Locked and holding nothing.
    func showsClipsOutsideSettingChanged() {
        guard historyLock.isEnabled else { return }
        if historyLock.holdsOutsideSurfaces { emptyOutsideSurfaces() } else { writeOutsideSurfaces() }
    }

    private func emptyOutsideSurfaces() {
        guard historyLock.holdsOutsideSurfaces else { return }
        emptyQuickInsert()
        if let widget, widgetIsInstalled || widget.file.exists { performWidgetEmpty() }
    }

    private func writeOutsideSurfaces() {
        writeQuickInsert()
        Task { await refreshWidgetPresence() }
    }
}
