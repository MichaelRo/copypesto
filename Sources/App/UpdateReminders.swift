// SPDX-License-Identifier: MIT
import Sparkle

/// Pesto has no Dock icon, so Sparkle's scheduled update window can open behind other windows with nothing to say it
/// exists. This takes over showing a scheduled update when the person is not looking: the status menu gets an
/// "Update Available" item at the top, which opens Sparkle's own window on a click (Sparkle's gentle reminders).
@MainActor
final class UpdateReminders: NSObject, SPUStandardUserDriverDelegate, SPUUpdaterDelegate {
    private let appState: AppState
    var onUpToDate: (() -> Void)?
    var onUpdateReady: ((_ install: @escaping () -> Void) -> Void)?
    private(set) var hasPendingManualCheck = false

    init(appState: AppState) {
        self.appState = appState
    }

    func beginManualCheck() {
        hasPendingManualCheck = true
    }

    nonisolated var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    )
    -> Bool {
        MainActor.assumeIsolated {
            hasPendingManualCheck || immediateFocus
        }
    }

    private nonisolated func onMain(_ work: @escaping @MainActor (UpdateReminders) -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { work(self) }
        } else {
            Task { @MainActor in work(self) }
        }
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state _: SPUUserUpdateState
    ) {
        let version = update.displayVersionString
        onMain {
            $0.hasPendingManualCheck = false
            $0.appState.availableUpdateVersion = handleShowingUpdate ? nil : version
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate _: SUAppcastItem) {
        onMain { $0.appState.availableUpdateVersion = nil }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        onMain {
            $0.hasPendingManualCheck = false
            $0.appState.availableUpdateVersion = nil
        }
    }

    func handleNoUpdateFound(userInitiated: Bool = false) {
        let wasManual = hasPendingManualCheck || userInitiated
        hasPendingManualCheck = false
        if wasManual {
            onUpToDate?()
        }
    }

    func handleUpdateStaged(install: @escaping () -> Void) {
        guard hasPendingManualCheck else { return }
        hasPendingManualCheck = false
        onUpdateReady?(install)
    }

    /// With automatic updates on, Sparkle downloads a found update with no window, and a manual check would look as
    /// if nothing happened. Returning false leaves the install-on-quit as it was.
    nonisolated func updater(
        _: SPUUpdater,
        willInstallUpdateOnQuit _: SUAppcastItem,
        immediateInstallationBlock install: @escaping () -> Void
    )
    -> Bool {
        nonisolated(unsafe) let install = install
        onMain { $0.handleUpdateStaged(install: { install() }) }
        return false
    }

    nonisolated func updaterDidNotFindUpdate(_: SPUUpdater, error: any Error) {
        let userInitiated = (error as NSError).userInfo[SPUNoUpdateFoundUserInitiatedKey] as? Bool == true
        onMain { $0.handleNoUpdateFound(userInitiated: userInitiated) }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor _: SPUUpdateCheck, error _: (any Error)?) {
        let checked = updater.lastUpdateCheckDate
        onMain {
            $0.hasPendingManualCheck = false
            $0.appState.lastUpdateCheck = checked
        }
    }

    nonisolated func updater(_: SPUUpdater, didAbortWithError _: any Error) {
        onMain { $0.hasPendingManualCheck = false }
    }
}
