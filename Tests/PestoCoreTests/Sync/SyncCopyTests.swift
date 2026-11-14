// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Sync wording that depends on where the key lives")
struct SyncCopyTests {
    @Test("the set-up sheet promises 'nothing typed' only when the key travels in iCloud Keychain")
    func keyLine() {
        #expect(SyncCopy.keyLine(.iCloudKeychain).contains("iCloud Keychain"))
        #expect(SyncCopy.keyLine(.iCloudKeychain).contains("needs nothing typed"))
        let local = SyncCopy.keyLine(.thisDevice)
        #expect(!local.contains("needs nothing typed"))
        #expect(local.contains("recovery key"))
        #expect(local.contains("checking the words"))
    }

    @Test(
        "Reset Sync: other Macs join again alone only with iCloud Keychain, otherwise they need the new key"
    )
    func resetMessage() {
        let shared = SyncCopy.resetMessage(.iCloudKeychain)
        #expect(shared.contains("join again on their next launch"))
        let local = SyncCopy.resetMessage(.thisDevice)
        #expect(!local.contains("join again on their next launch"))
        #expect(local.contains("new recovery key"))
        for mode in [SyncKeyMode.iCloudKeychain, .thisDevice] {
            #expect(SyncCopy.resetMessage(mode).contains("keeps everything it has"))
        }
    }

    @Test("one word for the idea: Macs are kept matching, never alike")
    func vocabulary() {
        let all = [
            SyncCopy.intro, SyncCopy.offDetail, SyncCopy.keyLine(.iCloudKeychain), SyncCopy.keyLine(.thisDevice),
            SyncCopy.resetMessage(.iCloudKeychain), SyncCopy.resetMessage(.thisDevice), SyncCopy.keychainOffLead
        ]
        for line in all {
            #expect(!line.contains("alike"), "\(line)")
        }
        #expect(SyncCopy.intro.contains("matching"))
        #expect(!SyncCopy.keychainOffLead.contains("Nothing has been sent"))
    }

    @Test("the key sheets name iCloud Keychain only when this build could have used it")
    func keySheets() {
        #expect(SyncCopy.recoveryKeyLead(.iCloudKeychain).contains("iCloud Keychain is unavailable"))
        #expect(!SyncCopy.recoveryKeyLead(.thisDevice).contains("iCloud Keychain"))
        #expect(SyncCopy.recoveryKeyLead(.thisDevice).contains("another Mac"))
        #expect(SyncCopy.needsKeyLead(.iCloudKeychain).contains("iCloud Keychain"))
        #expect(!SyncCopy.needsKeyLead(.thisDevice).contains("iCloud Keychain"))
    }

    @Test("a Mac reads exactly the sentences it always had")
    func whenTheDeviceIsAMac_thenTheWordingIsUnchanged() {
        #expect(SyncCopy.intro == "Pesto keeps your clips matching on the Macs where you turn this on.")
        #expect(SyncCopy.offDetail == "Turn it on to keep your Macs matching.")
        #expect(
            SyncCopy.keychainOffLead
                == "Sync needs iCloud Keychain to share its key between your Macs. Nothing has been written."
        )
        #expect(
            SyncCopy.keyLine(.iCloudKeychain) == "The key lives in iCloud Keychain, so a new Mac needs nothing typed."
        )
        #expect(
            SyncCopy.keyLine(.thisDevice) == "The key stays on this Mac. A new Mac joins with the recovery key, "
                + "or you approve it here after checking the words."
        )
        #expect(
            SyncCopy.resetMessage(.thisDevice) == "Every Mac gets a new key. A Mac you removed from your Apple Account "
                + "stops receiving clips. This Mac keeps everything it has. Each other Mac needs the new recovery key, "
                + "or your approval, to join again."
        )
        #expect(
            SyncCopy.resetMessage(.iCloudKeychain).hasSuffix("Your other Macs join again on their next launch.")
        )
        #expect(
            SyncCopy.recoveryKeyLead(.thisDevice) == "This key opens your sync folder on another Mac. "
                + "Keep it in your password manager. Pesto cannot recover it for you."
        )
        #expect(
            SyncCopy.needsKeyLead(.thisDevice)
                == "This Mac does not have the key, so another Mac has to hand it over, or you enter it."
        )
        #expect(
            SyncCopy.needsKeyLead(.iCloudKeychain)
                == "This Mac cannot get the key from iCloud Keychain, so another Mac has to hand it over."
        )
        #expect(
            SyncCopy.noOtherDevice()
                == "No other Mac has announced itself in this folder yet. Open Pesto on the other Mac first."
        )
        #expect(SyncCopy.grantDidNotOpen() == "The key from the other Mac did not open. Ask again.")
        #expect(
            SyncCopy.couldNotLeave() == "Pesto could not remove this Mac's files from the folder, so sync is still on. "
        )
        #expect(SyncCopy.keychainLocked() == "The Keychain is locked. Unlock the Mac and try again.")
        #expect(
            SyncCopy.refusal(.badSignature)
                == "A file from another Mac did not match its signature. Nothing was changed."
        )
        #expect(
            SyncCopy.refusal(.otherGroup) == "This folder holds a different sync from the one this Mac joined. "
                + "Nothing was changed. To use it, choose Leave Sync here first."
        )
    }

    private static func everySentence(_ device: SyncDeviceKind) -> [String] {
        let modes = [SyncKeyMode.iCloudKeychain, .thisDevice]
        let errors: [SyncError] = [
            .badSignature, .unknownSigner, .fork, .clockFarAhead, .wrongKey, .vaultWentBack, .otherGroup
        ]
        return [
            SyncCopy.intro(device), SyncCopy.offDetail(device), SyncCopy.keychainOffLead(device),
            SyncCopy.noOtherDevice(device), SyncCopy.grantDidNotOpen(device), SyncCopy.couldNotLeave(device),
            SyncCopy.keychainLocked(device)
        ] + modes.flatMap { mode in
            [
                SyncCopy.keyLine(mode, device: device), SyncCopy.resetMessage(mode, device: device),
                SyncCopy.recoveryKeyLead(mode, device: device), SyncCopy.needsKeyLead(mode, device: device)
            ]
        } + errors.map { SyncCopy.refusal($0, device: device) }
    }

    @Test("an iPhone and an iPad name themselves and call the others devices, never Macs", arguments: [
        SyncDeviceKind.iPhone, .iPad
    ])
    func whenTheDeviceIsNotAMac_thenNoSentenceSaysMac(_ device: SyncDeviceKind) {
        for line in Self.everySentence(device) {
            #expect(!line.contains("Mac"), "\(line)")
            #expect(!line.contains("alike"), "\(line)")
        }
        #expect(SyncCopy.keyLine(.thisDevice, device: device).contains("The key stays on this \(device.name)."))
        #expect(SyncCopy.needsKeyLead(.thisDevice, device: device).hasPrefix("This \(device.name) does not have"))
        #expect(SyncCopy.resetMessage(.thisDevice, device: device).contains("This \(device.name) keeps everything"))
        #expect(SyncCopy.couldNotLeave(device).contains("this \(device.name)'s files"))
        #expect(SyncCopy.refusal(.vaultWentBack, device: device).contains("than this \(device.name) has seen"))
        #expect(SyncCopy.keyLine(.iCloudKeychain, device: device).contains("needs nothing typed"))
        #expect(!SyncCopy.keyLine(.thisDevice, device: device).contains("needs nothing typed"))
    }
}
