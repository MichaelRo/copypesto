// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("BackupChip: what the summary and the fourth stat tile say about the backup")
struct BackupChipTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.gmt
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    private func chip(
        _ status: BackupStatus,
        last: Date? = nil,
        problem: BackupProblem? = nil
    )
    -> BackupChip {
        BackupChip(status: status, lastBackup: last, problem: problem)
    }

    @Test("no backup set up is off, and a stored problem does not matter")
    func whenOff_thenOff() {
        #expect(chip(.off) == .off)
        #expect(chip(.off, last: date(29, 12, 40), problem: .failed) == .off)
    }

    @Test("a backup that is on and has never written says it has not run yet")
    func whenOnWithoutAFile_thenWaiting() {
        #expect(chip(.on) == .waiting)
    }

    @Test("a backup that is on and wrote a file is up to date at that time")
    func whenOnWithAFile_thenUpToDate() {
        let written = date(29, 12, 40)
        #expect(chip(.on, last: written) == .upToDate(written))
    }

    @Test("a backup kept through Clear Everything is paused, even with a problem stored")
    func whenPaused_thenPaused() {
        #expect(chip(.paused, last: date(29, 12, 40)) == .paused)
        #expect(chip(.paused, problem: .refused) == .paused)
    }

    @Test("a stored problem on a running backup needs the person, whatever the last good time was")
    func whenAProblemIsStored_thenNeedsYou() {
        #expect(chip(.on, last: date(29, 12, 40), problem: .folderMissing) == .needsYou(.folderMissing))
        #expect(chip(.on, problem: .refused) == .needsYou(.refused))
    }

    @Test("the tile value is the time for a backup written today, the date for an older one")
    func tileValue() {
        let now = date(29, 15, 0)
        let locale = Locale(identifier: "en_GB")
        #expect(chip(.on, last: date(29, 12, 40)).tileValue(now: now, calendar: calendar, locale: locale) == "12:40")
        #expect(chip(.on, last: date(27, 9, 5)).tileValue(now: now, calendar: calendar, locale: locale) == "27 Oct")
        #expect(chip(.off).tileValue(now: now, calendar: calendar, locale: locale) == "Off")
        #expect(chip(.on).tileValue(now: now, calendar: calendar, locale: locale) == "Not yet")
        #expect(chip(.paused).tileValue(now: now, calendar: calendar, locale: locale) == "Paused")
        #expect(chip(.on, problem: .failed).tileValue(now: now, calendar: calendar, locale: locale) == "Needs you")
    }

    @Test("the tile label says what the value is")
    func tileLabel() {
        #expect(chip(.off).tileLabel == "Backup")
        #expect(chip(.on).tileLabel == "Backup")
        #expect(chip(.on, last: date(29, 12, 40)).tileLabel == "Backed up")
        #expect(chip(.paused).tileLabel == "Backup")
        #expect(chip(.on, problem: .failed).tileLabel == "Backup")
    }

    @Test("the summary chip is a short sentence with the state in it")
    func summaryText() {
        let now = date(29, 15, 0)
        let locale = Locale(identifier: "en_GB")
        func text(_ chip: BackupChip) -> String {
            chip.summaryText(now: now, calendar: calendar, locale: locale)
        }
        #expect(text(chip(.off)) == "Backup: Off")
        #expect(text(chip(.on)) == "Backup: Not written yet")
        #expect(text(chip(.on, last: date(29, 12, 40))) == "Backup: Up to date, saved at 12:40")
        #expect(text(chip(.paused)) == "Backup: Paused")
        #expect(text(chip(.on, problem: .folderMissing)) == "Backup: Folder Missing")
        #expect(text(chip(.on, problem: .failed)) == "Backup: Could Not Save")
        #expect(text(chip(.on, problem: .refused)) == "Backup: Needs You")
    }
}
