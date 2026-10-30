// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Automatic backup")
struct AutoBackupTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("nothing changed since the last backup means nothing to do")
    func whenNothingChanged_thenNoDelay() {
        #expect(AutoBackupPolicy.delay(lastChange: nil, lastBackup: nil, now: now) == nil)
        let backup = now.addingTimeInterval(-100)
        #expect(AutoBackupPolicy.delay(lastChange: backup.addingTimeInterval(-5), lastBackup: backup, now: now) == nil)
    }

    @Test("a change waits for a quiet five minutes before the first backup")
    func whenFirstChange_thenWaitsToSettle() {
        let change = now.addingTimeInterval(-60)
        #expect(AutoBackupPolicy.delay(lastChange: change, lastBackup: nil, now: now) == 240)
        #expect(AutoBackupPolicy.delay(lastChange: now.addingTimeInterval(-600), lastBackup: nil, now: now) == 0)
    }

    @Test("a backup is never closer than an hour to the last one")
    func whenRecentBackup_thenWaitsForTheInterval() {
        let backup = now.addingTimeInterval(-1200)
        let change = now.addingTimeInterval(-600)
        #expect(AutoBackupPolicy.delay(lastChange: change, lastBackup: backup, now: now) == 2400)
    }

    @Test("it can be switched on and off, and nothing is shared between two stores")
    func settings_roundTripPerStore() {
        let defaults = ThrowawayDefaults.make()
        let settings = AutoBackupSettings(defaults: defaults)
        #expect(!settings.isEnabled)
        #expect(settings.folder == nil)

        settings.isEnabled = true
        settings.folder = URL(fileURLWithPath: "/tmp/pesto-backups", isDirectory: true)
        settings.header = Data([1, 2, 3])
        settings.lastBackup = now
        settings.lastBytes = 42
        #expect(settings.isEnabled)
        #expect(settings.folder?.path == "/tmp/pesto-backups")
        #expect(settings.lastBackup == now && settings.lastBytes == 42)

        settings.turnOff()
        #expect(!settings.isEnabled)
        #expect(settings.header == nil)
    }

    @Test("the file is named for the Mac and cannot escape the folder")
    func fileName_isSafe() {
        #expect(AutoBackupSettings.legacyFileName(forMac: "Sam\u{2019}s MacBook Pro")
            == "Pesto Backup \u{2013} Sam\u{2019}s MacBook Pro.pestobackup")
        #expect(!AutoBackupSettings.fileName(forMac: "../etc/passwd", deviceID: "../x").contains("/"))
        #expect(AutoBackupSettings.legacyFileName(forMac: "  ") == "Pesto Backup \u{2013} Mac.pestobackup")
    }

    @Test("two Macs with the same name get different files")
    func fileName_differsByDevice() {
        let first = AutoBackupSettings.fileName(forMac: "MacBook Pro", deviceID: "3F2A9C41-0000-4000-8000-000000000001")
        let second = AutoBackupSettings.fileName(
            forMac: "MacBook Pro",
            deviceID: "9B7D1E05-0000-4000-8000-000000000002"
        )
        #expect(first != second)
        #expect(first == "Pesto Backup \u{2013} MacBook Pro (3F2A9C41).pestobackup")
    }

    @Test("a missing device id still gives a usable name")
    func fileName_withoutDeviceID() {
        #expect(AutoBackupSettings.fileName(forMac: "Mac", deviceID: "") == "Pesto Backup \u{2013} Mac.pestobackup")
    }

    @Test("iCloud Drive is the suggested folder only when this Mac has it")
    func iCloudFolder_isSuggestedWhenTheDriveExists() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-home-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        #expect(AutoBackupSettings.iCloudDriveFolder(home: home) == nil)

        let drive = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        #expect(AutoBackupSettings.iCloudDriveFolder(home: home)?.path == drive.appendingPathComponent("Pesto").path)
    }

    @Test("the next backup time is the delay from now, and nothing when there is nothing to back up")
    func nextBackup_isNowPlusTheDelay() {
        let change = now.addingTimeInterval(-60)
        #expect(AutoBackupPolicy.nextBackup(lastChange: change, lastBackup: nil, now: now) == now
            .addingTimeInterval(240))
        #expect(AutoBackupPolicy.nextBackup(lastChange: nil, lastBackup: nil, now: now) == nil)
    }

    @Test("a configured backup runs automatically unless the person turns that off, and says how it is protected")
    func settings_automaticAndProtection() {
        let defaults = ThrowawayDefaults.make()
        let settings = AutoBackupSettings(defaults: defaults)
        #expect(settings.runsAutomatically, "a backup that has been set up keeps itself up to date by default")
        #expect(settings.protection == nil)

        settings.runsAutomatically = false
        settings.protection = .recoveryKey
        #expect(!settings.runsAutomatically)
        #expect(settings.protection == .recoveryKey)

        settings.turnOff()
        #expect(settings.runsAutomatically, "turning the backup off forgets the choice")
        #expect(settings.protection == nil)
    }
}

@Suite("AutoBackupSettings: the last problem")
struct AutoBackupProblemTests {
    @Test("a problem is stored as a word, read back, and cleared with nil")
    func whenAProblemIsStored_thenItIsReadBack() {
        let defaults = ThrowawayDefaults.make()
        let settings = AutoBackupSettings(defaults: defaults)
        #expect(settings.problem == nil)
        settings.problem = .folderMissing
        #expect(settings.problem == .folderMissing)
        settings.problem = nil
        #expect(settings.problem == nil)
    }

    @Test("an unknown stored word is no problem, so an old or edited preference cannot show a wrong chip")
    func whenTheStoredWordIsUnknown_thenNoProblem() {
        let defaults = ThrowawayDefaults.make()
        defaults.set("exploded", forKey: AutoBackupSettings.problemKey)
        #expect(AutoBackupSettings(defaults: defaults).problem == nil)
    }

    @Test("turning the backup off forgets the problem")
    func whenTurnedOff_thenTheProblemIsForgotten() {
        let defaults = ThrowawayDefaults.make()
        let settings = AutoBackupSettings(defaults: defaults)
        settings.isEnabled = true
        settings.problem = .failed
        settings.turnOff()
        #expect(settings.problem == nil)
    }
}
