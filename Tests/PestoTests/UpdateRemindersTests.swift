// SPDX-License-Identifier: MIT
import Testing
@testable import Pesto

@MainActor
@Suite("Update reminders")
struct UpdateRemindersTests {
    @Test("a manual check that staged an update offers the restart, once")
    func whenManualCheckStagesUpdate_thenItOffersRestartOnce() {
        let reminders = UpdateReminders(appState: AppState())
        var offered = 0
        var installed = 0
        reminders.onUpdateReady = { _ in offered += 1 }
        reminders.beginManualCheck()

        let first = reminders.handleUpdateStaged(install: { installed += 1 })
        let second = reminders.handleUpdateStaged(install: { installed += 1 })

        #expect(first)
        #expect(!second)
        #expect(offered == 1)
        #expect(installed == 0)
        #expect(!reminders.hasPendingManualCheck)
    }

    @Test("an update staged by a scheduled check stays silent")
    func whenScheduledCheckStagesUpdate_thenNothingIsOffered() {
        let reminders = UpdateReminders(appState: AppState())
        var offered = 0
        reminders.onUpdateReady = { _ in offered += 1 }

        let tookOver = reminders.handleUpdateStaged(install: {})

        #expect(offered == 0)
        #expect(!tookOver)
    }

    @Test("the offer hands over the install action")
    func whenOffered_thenTheInstallActionRuns() {
        let reminders = UpdateReminders(appState: AppState())
        var installed = 0
        reminders.onUpdateReady = { install in install() }
        reminders.beginManualCheck()

        reminders.handleUpdateStaged(install: { installed += 1 })

        #expect(installed == 1)
    }
}
