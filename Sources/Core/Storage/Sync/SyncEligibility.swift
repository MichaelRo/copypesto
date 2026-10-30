// SPDX-License-Identifier: MIT
import Foundation

/// Which clips may leave this Mac (ADR 0018). A clip that holds a secret stays unless the person opted in to syncing
/// those; a credential (a password manager's copy kept under an allowance, ADR 0004) never goes; a clip over 10 MB
/// does not go; a clip that has not been judged yet waits, because its category is not known (ADR 0006).
public enum SyncEligibility {
    public enum Verdict: Equatable, Sendable {
        case send
        case waitForJudgment
        case staysHere(Reason)
    }

    public enum Reason: Equatable, Sendable {
        case sensitive
        case credential
        case tooLarge
    }

    public static func verdict(for item: ClipboardItem, includeSensitive: Bool) -> Verdict {
        if item.analysisPending { return .waitForJudgment }
        if item.sensitivityRaw == SensitivityCategory.credential.rawValue { return .staysHere(.credential) }
        if item.byteSize > AutoBackupSettings.largestClipBytes { return .staysHere(.tooLarge) }
        if item.sensitivityRaw != nil, !includeSensitive { return .staysHere(.sensitive) }
        return .send
    }

    /// A clip that was written to the log and now must not be there (it was marked sensitive after it synced, or the
    /// person turned the sensitive option off): the log gets a withdrawal, which the other Macs treat as a deletion.
    public static func needsWithdrawal(_ item: ClipboardItem, includeSensitive: Bool) -> Bool {
        guard item.syncEmittedClock != nil else { return false }
        if case .staysHere = verdict(for: item, includeSensitive: includeSensitive) { return true }
        return false
    }
}
