// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import Sparkle

extension AppDelegate {
    /// Lets Settings switch Sparkle's automatic checks on and off. They were on with no way to turn them off, in an
    /// app whose only other network request is one the person can disable too.
    func wireUpdateSettings() {
        let updater = updaterController.updater
        appState.lastUpdateCheck = updater.lastUpdateCheckDate
        wireUpdateFeedback()
        appState.automaticUpdateInstalls = (
            get: { updater.automaticallyDownloadsUpdates },
            set: { updater.automaticallyDownloadsUpdates = $0 }
        )
        appState.automaticUpdateChecks = (
            get: { updater.automaticallyChecksForUpdates },
            set: { updater.automaticallyChecksForUpdates = $0 }
        )
    }

    private func wireUpdateFeedback() {
        appState.checkForUpdates = { [weak self] in self?.statusCheckUpdates() }
        appState.updateReminders.onUpToDate = { [weak self] in self?.showUpToDateToast() }
        appState.updateReminders.onUpdateReady = { [weak self] install in self?.showUpdateReadyToast(install: install) }
    }

    /// A UI-test stand-in for Sparkle (`PESTO_UITEST_UPDATES`): the same app-side wiring, with a check that stages a
    /// fake update after a moment and an install that only writes to the command log.
    func wireFakeUpdatesForUITest() {
        wireUpdateFeedback()
        var checks = false
        var installs = false
        appState.automaticUpdateChecks = (get: { checks }, set: { checks = $0 })
        appState.automaticUpdateInstalls = (get: { installs }, set: { installs = $0 })
    }

    func runFakeUpdateCheck() {
        let reminders = appState.updateReminders
        reminders.beginManualCheck()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self else { return }
            appState.lastUpdateCheck = Date()
            reminders.stage(StagedUpdate(version: "9.9.9", fullNotes: nil, itemNotes: nil, install: {
                UITestSupport.appendCommandLog("update-install", in: AppPaths.supportDirectory)
            }))
        }
    }
}
