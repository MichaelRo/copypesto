// SPDX-License-Identifier: MIT
import Foundation

/// Sync sentences whose truth depends on where the key lives, so a view cannot promise what the build cannot do. A Mac
/// reads the sentences it always had; an iPhone or iPad names itself and calls the others devices.
public enum SyncCopy {
    public static func intro(_ device: SyncDeviceKind) -> String {
        switch device {
        case .mac: String(localized: "Pesto keeps your clips matching on the Macs where you turn this on.")
        case .iPhone, .iPad: String(localized: "Pesto keeps your clips matching on the devices where you turn this on.")
        }
    }

    public static var intro: String {
        intro(.mac)
    }

    public static func offDetail(_ device: SyncDeviceKind) -> String {
        switch device {
        case .mac: String(localized: "Turn it on to keep your Macs matching.")
        case .iPhone, .iPad: String(localized: "Turn it on to keep your devices matching.")
        }
    }

    public static var offDetail: String {
        offDetail(.mac)
    }

    public static func keychainOffLead(_ device: SyncDeviceKind) -> String {
        switch device {
        case .mac:
            String(
                localized: "Sync needs iCloud Keychain to share its key between your Macs. Nothing has been written."
            )
        case .iPhone, .iPad:
            String(
                localized: "Sync needs iCloud Keychain to share its key between your devices. Nothing has been written."
            )
        }
    }

    public static var keychainOffLead: String {
        keychainOffLead(.mac)
    }

    public static func keyLine(_ mode: SyncKeyMode, device: SyncDeviceKind = .mac) -> String {
        let this = device.thisDevice
        switch (mode, device) {
        case (.iCloudKeychain, .mac):
            return String(localized: "The key lives in iCloud Keychain, so a new Mac needs nothing typed.")
        case (.iCloudKeychain, _):
            return String(localized: "The key lives in iCloud Keychain, so a new device needs nothing typed.")
        case (.thisDevice, .mac):
            return [
                String(localized: "The key stays on this Mac."),
                String(
                    localized: "A new Mac joins with the recovery key, or you approve it here after checking the words."
                )
            ].joined(separator: " ")
        case (.thisDevice, _):
            return [
                String(localized: "The key stays on \(this)."),
                String(localized: "A new device joins with the recovery key,"),
                String(localized: "or you approve it here after checking the words.")
            ].joined(separator: " ")
        }
    }

    public static func resetMessage(_ mode: SyncKeyMode, device: SyncDeviceKind = .mac) -> String {
        if device == .mac {
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
        let common = [
            String(localized: "Every device gets a new key."),
            String(localized: "A device you removed from your Apple Account stops receiving clips."),
            String(localized: "This \(device.name) keeps everything it has.")
        ]
        let rest = switch mode {
        case .iCloudKeychain: String(localized: "Your other devices join again the next time Pesto opens on them.")
        case .thisDevice: String(
                localized: "Each other device needs the new recovery key, or your approval, to join again."
            )
        }
        return (common + [rest]).joined(separator: " ")
    }

    public static func recoveryKeyLead(_ mode: SyncKeyMode, device: SyncDeviceKind = .mac) -> String {
        let keep = String(localized: "Keep it in your password manager. Pesto cannot recover it for you.")
        let opens = switch (mode, device) {
        case (.iCloudKeychain, _):
            String(localized: "This key opens your sync folder if iCloud Keychain is unavailable.")
        case (.thisDevice, .mac):
            String(localized: "This key opens your sync folder on another Mac.")
        case (.thisDevice, _):
            String(localized: "This key opens your sync folder on another device.")
        }
        return opens + " " + keep
    }

    public static func needsKeyLead(_ mode: SyncKeyMode, device: SyncDeviceKind = .mac) -> String {
        let this = device.name
        switch (mode, device) {
        case (.iCloudKeychain, .mac):
            return String(
                localized: "This Mac cannot get the key from iCloud Keychain, so another Mac has to hand it over."
            )
        case (.iCloudKeychain, _):
            return String(localized: "This \(this) cannot get the key from iCloud Keychain,") + " "
                + String(localized: "so another device has to hand it over.")
        case (.thisDevice, .mac):
            return String(
                localized: "This Mac does not have the key, so another Mac has to hand it over, or you enter it."
            )
        case (.thisDevice, _):
            return String(
                localized: "This \(this) does not have the key, so another device has to hand it over, or you enter it."
            )
        }
    }

    public static func noOtherDevice(_ device: SyncDeviceKind = .mac) -> String {
        switch device {
        case .mac: "No other Mac has announced itself in this folder yet. Open Pesto on the other Mac first."
        case .iPhone, .iPad:
            "No other device has announced itself in this folder yet. Open Pesto on the other device first."
        }
    }

    public static func grantDidNotOpen(_ device: SyncDeviceKind = .mac) -> String {
        switch device {
        case .mac: "The key from the other Mac did not open. Ask again."
        case .iPhone, .iPad: "The key from the other device did not open. Ask again."
        }
    }

    public static func couldNotLeave(_ device: SyncDeviceKind = .mac) -> String {
        "Pesto could not remove \(device.thisDevice)'s files from the folder, so sync is still on. "
    }

    public static func keychainLocked(_ device: SyncDeviceKind = .mac) -> String {
        "The Keychain is locked. Unlock the \(device.name) and try again."
    }

    public static func refusal(_ error: SyncError, device: SyncDeviceKind = .mac) -> String {
        let other = device == .mac ? "Mac" : "device"
        let this = device.thisDevice
        return switch error {
        case .badSignature: "A file from another \(other) did not match its signature. Nothing was changed."
        case .unknownSigner: "A file came from a \(other) this sync does not know. Nothing was changed."
        case .fork, .rollback, .brokenChain:
            "Another \(other)'s log went backwards or was changed. Nothing was changed."
        case .clockFarAhead: "Another \(other)'s clock is far ahead, so its changes were not applied."
        case .wrongVault, .wrongEpoch, .wrongKey: "Sync was reset. It will pick up the new key."
        case .vaultWentBack:
            "The sync folder went back to an older state than \(this) has seen. Nothing was changed. "
                + "If you reset sync on purpose, choose Leave Sync here and join again."
        case .otherGroup:
            "This folder holds a different sync from the one \(this) joined. Nothing was changed. "
                + "To use it, choose Leave Sync here first."
        default: "A file from another \(other) is damaged. Nothing was changed."
        }
    }
}
