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

    /// Keeps the staged update for the menu and Settings, and offers the restart when a manual check found it.
    func stage(_ update: StagedUpdate) {
        appState.stagedUpdate = update
        guard hasPendingManualCheck else { return }
        hasPendingManualCheck = false
        onUpdateReady?(update.install)
    }

    /// With automatic updates on, Sparkle downloads a found update with no window, and a check would look as if
    /// nothing happened. Answering true is what makes Sparkle honor the install handler; the update still installs
    /// on quit, and later scheduled cycles stall because this one has the update.
    nonisolated func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock install: @escaping () -> Void
    )
    -> Bool {
        guard Thread.isMainThread else { return false }
        nonisolated(unsafe) let install = install
        let checked = updater.lastUpdateCheckDate
        let version = item.displayVersionString
        let fullNotes = item.fullReleaseNotesURL
        let itemNotes = item.releaseNotesURL
        MainActor.assumeIsolated {
            appState.lastUpdateCheck = checked
            stage(StagedUpdate(version: version, fullNotes: fullNotes, itemNotes: itemNotes, install: { install() }))
        }
        return true
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
