// SPDX-License-Identifier: MIT
import AppKit
import Foundation
import Testing
@testable import Pesto

@MainActor
@Suite("Update reminders")
struct UpdateRemindersTests {
    private func update(install: @escaping () -> Void = {}) -> StagedUpdate {
        StagedUpdate(version: "1.4.0", fullNotes: nil, itemNotes: nil, install: install)
    }

    @Test("a manual check that staged an update offers the restart, once")
    func whenManualCheckStagesUpdate_thenItOffersRestartOnce() {
        let reminders = UpdateReminders(appState: AppState())
        var offered = 0
        reminders.onUpdateReady = { _ in offered += 1 }
        reminders.beginManualCheck()

        reminders.stage(update())
        reminders.stage(update())

        #expect(offered == 1)
        #expect(!reminders.hasPendingManualCheck)
    }

    @Test("an update staged by a scheduled check stays silent but is kept for the menu")
    func whenScheduledCheckStagesUpdate_thenNothingIsOfferedButItIsKept() {
        let state = AppState()
        var offered = 0
        state.updateReminders.onUpdateReady = { _ in offered += 1 }

        state.updateReminders.stage(update())

        #expect(offered == 0)
        #expect(state.stagedUpdate?.version == "1.4.0")
    }

    @Test("the offer hands over the install action")
    func whenOffered_thenTheInstallActionRuns() {
        let reminders = UpdateReminders(appState: AppState())
        var installed = 0
        reminders.onUpdateReady = { install in install() }
        reminders.beginManualCheck()

        reminders.stage(update { installed += 1 })

        #expect(installed == 1)
    }

    @Test("the what's-new link prefers the full notes, then the item's, then the releases page")
    func whenNotesMissing_thenItFallsBackToTheReleasesPage() throws {
        let full = try #require(URL(string: "https://copypesto.net/releases/full"))
        let item = try #require(URL(string: "https://copypesto.net/releases/item"))

        #expect(StagedUpdate(version: "1", fullNotes: full, itemNotes: item, install: {}).whatsNew == full)
        #expect(StagedUpdate(version: "1", fullNotes: nil, itemNotes: item, install: {}).whatsNew == item)
        let neither = StagedUpdate(version: "1", fullNotes: nil, itemNotes: nil, install: {})
        #expect(neither.whatsNew == StagedUpdate.releasesPage)
    }

    @Test("the menu offers Restart to Update and What's New while an update is staged, and not otherwise")
    func whenUpdateStaged_thenTheMenuOffersIt() {
        let delegate = AppDelegate()
        let menu = NSMenu()
        delegate.menuNeedsUpdate(menu)
        #expect(!menu.items.map(\.title).contains("Restart to Update\u{2026}"))

        delegate.appState.stagedUpdate = update()
        delegate.menuNeedsUpdate(menu)
        let titles = menu.items.map(\.title)
        #expect(titles.contains("Restart to Update\u{2026}"))
        #expect(titles.contains("What\u{2019}s New\u{2026}"))
    }

    @Test("the menu's Restart to Update runs the staged install")
    func whenRestartChosen_thenTheInstallRuns() {
        let delegate = AppDelegate()
        var installed = 0
        delegate.appState.stagedUpdate = update { installed += 1 }

        delegate.statusInstallStagedUpdate()

        #expect(installed == 1)
    }
}
