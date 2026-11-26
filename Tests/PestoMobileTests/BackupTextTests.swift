// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("What the iOS backup screens say")
struct BackupTextTests {
    @Test("Back Up needs a strong passphrase typed twice, or the recovery key alone")
    func canBackUp_followsTheProtection() {
        let strong = "basil garlic pine nuts parmesan"
        #expect(BackupText.canBackUp(protection: .passphrase, passphrase: strong, confirmation: strong))
        #expect(!BackupText.canBackUp(protection: .passphrase, passphrase: strong, confirmation: "basil"))
        #expect(!BackupText.canBackUp(protection: .passphrase, passphrase: "short", confirmation: "short"))
        #expect(BackupText.canBackUp(protection: .recoveryKey, passphrase: "", confirmation: ""))
    }

    @Test("the hint says when the two passphrases differ, else how strong it is")
    func passphraseHint_namesTheProblem() {
        #expect(BackupText.passphraseHint("basil garlic pine", confirmation: "basil garlic pino")
            == "The two passphrases are different.")
        #expect(BackupText.passphraseHint("short", confirmation: "") == "Use at least 12 characters, or four words.")
        let strong = "basil garlic pine nuts parmesan"
        #expect(BackupText.passphraseHint(strong, confirmation: strong) == "Strong.")
    }

    @Test("each kind of clip left out gets its own sentence, and nothing is said when none was")
    func leftOut_listsEachReason() {
        #expect(BackupText.leftOut(BackupExportSummary()).isEmpty)
        var summary = BackupExportSummary()
        summary.skippedSensitive = 1
        summary.skippedTooLarge = 2
        summary.skippedUnreadable = 3
        #expect(BackupText.leftOut(summary) == [
            "1 clip with a secret was left out.",
            "2 clips over 10 MB, such as large pictures, are left out.",
            "3 could not be read and were left out."
        ])
    }

    @Test("a count of nothing is left out of a sentence, except the clips")
    func counts_leaveOutZeros() {
        #expect(BackupText.counts(clips: 2, collections: 0) == "2 clips")
        #expect(BackupText.counts(clips: 0, collections: 1, deletions: 3) == "0 clips, 1 collection, and 3 deletions")
        var summary = BackupExportSummary()
        summary.items = 2
        #expect(BackupText.written(summary) == "This backup holds 2 clips.")
    }

    @Test("a restore that brought nothing new says so instead of counting zeros")
    func restored_nothingNew() {
        var summary = BackupRestoreSummary()
        summary.alreadyHad = 2
        #expect(BackupText.restored(summary) == "Nothing new to restore. 2 were already here.")
        summary.restored = 1
        #expect(BackupText.restored(summary) == "Restored 1 clip. 2 were already here.")
        summary.alreadyHad = 0
        #expect(BackupText.restored(summary) == "Restored 1 clip.")
    }

    @Test("a restore that could not bring every clip back says how many")
    func restored_mentionsFailures() {
        var summary = BackupRestoreSummary()
        summary.restored = 2
        summary.alreadyHad = 1
        #expect(!BackupText.restored(summary).contains("could not be restored"))
        summary.failed = 1
        #expect(BackupText.restored(summary).hasSuffix("1 clip could not be restored."))
    }

    @Test("each reason a file did not open is told apart", arguments: [
        BackupError.wrongCredential, .malformedRecoveryKey, .unsupportedVersion(2), .notABackup
    ])
    func openFailure_isSpecific(error: BackupError) {
        let generic = BackupText.openFailure(CocoaError(.fileReadUnknown))
        #expect(BackupText.openFailure(error) != generic)
    }

    @Test("a damaged file and a file that is not a backup read the same")
    func openFailure_corruptedIsNotABackup() {
        #expect(BackupText.openFailure(BackupError.corrupted) == BackupText.openFailure(BackupError.notABackup))
    }
}
