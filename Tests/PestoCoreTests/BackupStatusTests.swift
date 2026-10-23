// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("BackupStatus: whether a backup is on, paused or off")
struct BackupStatusTests {
    @Test("no backup set up is off, whatever else is stored")
    func whenNotConfigured_thenOff() {
        #expect(BackupStatus(isEnabled: false, pausedAfterClear: false) == .off)
        #expect(BackupStatus(isEnabled: false, pausedAfterClear: true) == .off)
    }

    @Test("a backup that is set up and running is on")
    func whenConfigured_thenOn() {
        #expect(BackupStatus(isEnabled: true, pausedAfterClear: false) == .on)
    }

    @Test("a backup kept through Clear Everything is paused until the person resumes it")
    func whenKeptAfterClear_thenPaused() {
        #expect(BackupStatus(isEnabled: true, pausedAfterClear: true) == .paused)
    }

    @Test("each state has a short word for the stat tile and a sentence for the header")
    func wordsAndSentences() {
        #expect(BackupStatus.on.word == "On")
        #expect(BackupStatus.paused.word == "Paused")
        #expect(BackupStatus.off.word == "Off")
        #expect(BackupStatus.on.title == "Backup is on")
        #expect(BackupStatus.paused.title == "Backup is paused")
        #expect(BackupStatus.off.title == "Backup is off")
    }

    @Test("the last backup reads as a relative time, or says it has not run yet")
    func lastBackupText() {
        #expect(BackupStatus.lastBackupText(nil) == "Not yet")
        #expect(!BackupStatus.lastBackupText(Date.now.addingTimeInterval(-120)).isEmpty)
    }
}
