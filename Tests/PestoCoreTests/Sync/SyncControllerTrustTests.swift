// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Sync controller: what a joined Mac trusts in the folder", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct SyncControllerTrustTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pesto-trust-\(UUID().uuidString)")
    let time = TimeBox()

    private func settle(_ mac: SyncMac) async {
        for _ in 0..<2 {
            time.advance()
            await mac.controller.syncNow()
        }
    }

    @Test("a request dated in the future is not shown: its date is the requester's own claim")
    func futureDatedRequestIsNotFresh() {
        let now = time.now
        let keys = SyncDeviceKeys.generate().publicKeys
        func request(at date: Date) -> SyncJoinRequest {
            SyncJoinRequest(deviceID: "mac-b", name: "b", keys: keys, vaultID: Data(count: 16), createdAt: date)
        }

        #expect(SyncController.isFresh(request(at: now), now: now))
        #expect(SyncController.isFresh(
            request(at: now.addingTimeInterval(SyncController.joinRequestClockSkew - 1)),
            now: now
        ))
        #expect(!SyncController.isFresh(
            request(at: now.addingTimeInterval(SyncController.joinRequestClockSkew + 1)),
            now: now
        ))
        #expect(!SyncController.isFresh(request(at: now.addingTimeInterval(365 * 24 * 3600)), now: now))
    }

    @Test("a vault planted beside the real one does not take the recovery key or the approving away from a joined Mac")
    func plantedVaultDoesNotHideTheGroup() async throws {
        let a = try SyncMac(name: "mac-a", folder: folder, time: time)
        await a.controller.turnOn()
        await settle(a)
        let key = a.controller.showRecoveryKey()
        #expect(key != nil)
        let creator = SyncDeviceKeys.generate()
        let planted = SyncVault.create(
            vaultID: Data(repeating: 0, count: 16), epoch: 7, syncKey: .generate(), creator: creator
        )
        try planted.serialized(signedBy: creator).write(to: SyncFolderLayout(root: folder).vault(epoch: 7))

        #expect(a.controller.showRecoveryKey() == key)
    }
}
