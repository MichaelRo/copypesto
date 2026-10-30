// SPDX-License-Identifier: MIT
import Foundation

/// Sync sentences whose truth depends on where the key lives, so a view cannot promise what the build cannot do.
public enum SyncCopy {
    public static var intro: String {
        String(localized: "Pesto keeps your clips matching on the Macs where you turn this on.")
    }

    public static var offDetail: String {
        String(localized: "Turn it on to keep your Macs matching.")
    }

    public static var keychainOffLead: String {
        String(localized: "Sync needs iCloud Keychain to share its key between your Macs. Nothing has been written.")
    }

    public static func keyLine(_ mode: SyncKeyMode) -> String {
        switch mode {
        case .iCloudKeychain:
            String(localized: "The key lives in iCloud Keychain, so a new Mac needs nothing typed.")
        case .thisDevice:
            [
                String(localized: "The key stays on this Mac."),
                String(
                    localized: "A new Mac joins with the recovery key, or you approve it here after checking six words."
                )
            ].joined(separator: " ")
        }
    }

    public static func resetMessage(_ mode: SyncKeyMode) -> String {
        let common = [
            String(localized: "Every Mac gets a new key."),
            String(localized: "A Mac you removed from your Apple Account stops receiving clips."),
            String(localized: "This Mac keeps everything it has.")
        ]
        let rest = switch mode {
        case .iCloudKeychain: String(localized: "Your other Macs join again on their next launch.")
        case .thisDevice: String(
                localized: "Each other Mac needs the new recovery key, or your approval, to join again."
            )
        }
        return (common + [rest]).joined(separator: " ")
    }

    public static func recoveryKeyLead(_ mode: SyncKeyMode) -> String {
        let keep = String(localized: "Keep it in your password manager. Pesto cannot recover it for you.")
        let opens = switch mode {
        case .iCloudKeychain: String(localized: "This key opens your sync folder if iCloud Keychain is unavailable.")
        case .thisDevice: String(localized: "This key opens your sync folder on another Mac.")
        }
        return opens + " " + keep
    }

    public static func needsKeyLead(_ mode: SyncKeyMode) -> String {
        switch mode {
        case .iCloudKeychain:
            String(localized: "This Mac cannot get the key from iCloud Keychain, so another Mac has to hand it over.")
        case .thisDevice:
            String(localized: "This Mac does not have the key, so another Mac has to hand it over, or you enter it.")
        }
    }
}
