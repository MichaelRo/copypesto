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
