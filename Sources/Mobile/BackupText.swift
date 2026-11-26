// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// What the iOS backup screens say, decided here where the tests reach it (ADR 0078).
enum BackupText {
    static let notOnDisk =
        String(localized: "Pesto can\u{2019}t back up or restore while your history is not saved on this device.")
    static let backUpFailed = String(localized: "Couldn\u{2019}t back up the history.")
    static let restoreFailed = String(localized: "Couldn\u{2019}t restore that backup.")

    /// Back Up is offered once the protection is complete: a passphrase that is long enough and typed twice the same,
    /// or the recovery key alone.
    static func canBackUp(
        protection: AutoBackupSettings.Protection, passphrase: String, confirmation: String
    )
    -> Bool {
        switch protection {
        case .recoveryKey: true
        case .passphrase: PassphraseStrength.evaluate(passphrase).isAcceptable && passphrase == confirmation
        }
    }

    /// The line under the passphrase fields, the same words as the Mac's Set Up Backup.
    static func passphraseHint(_ passphrase: String, confirmation: String) -> String {
        if !passphrase.isEmpty, passphrase != confirmation, confirmation.count >= passphrase.count {
            return String(localized: "The two passphrases are different.")
        }
        return switch PassphraseStrength.evaluate(passphrase) {
        case .tooShort: String(localized: "Use at least 12 characters, or four words.")
        case .weak: String(localized: "Too easy to guess. Try a few unrelated words.")
        case .fair: String(localized: "Not strong enough yet. Four unrelated words work well, or use a recovery key.")
        case .strong: String(localized: "Strong.")
        }
    }

    /// The clips a backup could not carry, one sentence each, in the order the person can act on.
    static func leftOut(_ summary: BackupExportSummary) -> [String] {
        var lines: [String] = []
        if summary.skippedSensitive > 0 {
            lines.append(String(localized: "\(summary.skippedSensitive) clips with secrets were left out."))
        }
        if summary.skippedTooLarge > 0 {
            lines
                .append(
                    String(
                        localized: "\(summary.skippedTooLarge) clips over 10 MB, such as large pictures, are left out."
                    )
                )
        }
        if summary.skippedUnreadable > 0 {
            lines.append(String(localized: "\(summary.skippedUnreadable) could not be read and were left out."))
        }
        return lines
    }

    static func written(_ summary: BackupExportSummary) -> String {
        let words = CountText.list([CountText.clips(summary.items), CountText.collections(summary.collections)])
        return String(localized: "This backup holds \(words).")
    }

    static func saved(_ summary: BackupExportSummary) -> String {
        ([String(localized: "Backup saved with \(CountText.clips(summary.items)).")] + leftOut(summary))
            .joined(separator: " ")
    }

    static func contents(of preview: BackupPreview) -> String {
        CountText.list([
            CountText.clips(preview.itemCount), CountText.collections(preview.collectionCount),
            CountText.deletions(preview.deletionCount)
        ])
    }

    /// What the file holds and what a restore would do here, the first line the plain facts.
    static func previewLines(_ preview: BackupPreview, counts: BackupRestorePreview?) -> [String] {
        let saved = preview.createdAt.formatted(date: .abbreviated, time: .shortened)
        var lines = [String(localized: "\(contents(of: preview)), saved \(saved).")]
        guard let counts else { return lines }
        let added = CountText.clips(counts.wouldAdd)
        lines.append(String(localized: "Up to \(added) would be added. \(CountText.alreadyHere(counts.alreadyHere))"))
        if counts.deletedHere > 0 {
            lines.append(String(localized: "\(CountText.clips(counts.deletedHere)) you deleted stay deleted."))
        }
        if counts.wouldRemove > 0 {
            let removed = CountText.clips(counts.wouldRemove)
            lines.append(String(
                localized: "\(removed) here were deleted where this backup was made, and would be removed."
            ))
        }
        return lines
    }

    static func restored(_ summary: BackupRestoreSummary) -> String {
        let words = CountText.list([CountText.clips(summary.restored), CountText.collections(summary.collections)])
        var text = String(localized: "Restored \(words). \(CountText.alreadyHere(summary.alreadyHad))")
        if summary.failed > 0 {
            text += " " + String(localized: "\(CountText.clips(summary.failed)) could not be restored.")
        }
        return text
    }

    /// Why a file did not open, in words that say what to try next.
    static func openFailure(_ error: any Error) -> String {
        switch error as? BackupError {
        case .wrongCredential:
            String(localized: "That passphrase or recovery key does not open this backup.")
        case .malformedRecoveryKey:
            String(localized: "That recovery key is not complete. Check each group of four characters.")
        case .unsupportedVersion:
            String(localized: "This backup was made by a newer Pesto. Update Pesto, then try again.")
        case .notABackup, .corrupted:
            String(localized: "This file is not a Pesto backup, or it is damaged.")
        case nil:
            String(localized: "Couldn\u{2019}t open that file. Check that it has finished downloading, then try again.")
        }
    }
}
