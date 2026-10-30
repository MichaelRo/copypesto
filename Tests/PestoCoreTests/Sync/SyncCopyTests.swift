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
        #expect(local.contains("six words"))
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
}
