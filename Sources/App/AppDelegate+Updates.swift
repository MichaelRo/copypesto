// SPDX-License-Identifier: MIT
import Sparkle

extension AppDelegate {
    /// Lets Settings switch Sparkle's automatic checks on and off. They were on with no way to turn them off, in an
    /// app whose only other network request is one the person can disable too.
    func wireUpdateSettings() {
        let updater = updaterController.updater
        appState.lastUpdateCheck = updater.lastUpdateCheckDate
        appState.checkForUpdates = { [weak self] in self?.statusCheckUpdates() }
        appState.updateReminders.onUpToDate = { [weak self] in self?.showUpToDateToast() }
        appState.updateReminders.onUpdateReady = { [weak self] install in self?.showUpdateReadyToast(install: install) }
        appState.automaticUpdateInstalls = (
            get: { updater.automaticallyDownloadsUpdates },
            set: { updater.automaticallyDownloadsUpdates = $0 }
        )
        appState.automaticUpdateChecks = (
            get: { updater.automaticallyChecksForUpdates },
            set: { updater.automaticallyChecksForUpdates = $0 }
        )
    }
}
