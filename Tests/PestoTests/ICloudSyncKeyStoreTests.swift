// SPDX-License-Identifier: MIT
import Foundation
import Security
import XCTest
@testable import PestoCore

final class ICloudSyncKeyStoreTests: XCTestCase {
    func test_whenSignedWithEntitlement_thenICloudKeyStoreSavesIdempotentlyDetectsConflictAndCleansUp() throws {
        try XCTSkipUnless(
            SyncEntitlement.isPresent,
            "iCloud Keychain sync requires the application-identifier entitlement"
        )

        let store = ICloudSyncKeyStore()
        let vaultID = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let epoch: UInt32 = 1
        let key = SyncKey.generate()
        let otherKey = SyncKey.generate()

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppIdentity.keychainService,
            kSecAttrAccount as String: ICloudSyncKeyStore.account(vaultID: vaultID, epoch: epoch),
            kSecAttrSynchronizable as String: true,
            kSecUseDataProtectionKeychain as String: true
        ]
        defer { SecItemDelete(deleteQuery as CFDictionary) }
        SecItemDelete(deleteQuery as CFDictionary)

        try store.saveSyncKey(key, vaultID: vaultID, epoch: epoch)
        XCTAssertEqual(try store.syncKey(vaultID: vaultID, epoch: epoch), key)

        // Duplicate write with the identical key is idempotent.
        try store.saveSyncKey(key, vaultID: vaultID, epoch: epoch)
        XCTAssertEqual(try store.syncKey(vaultID: vaultID, epoch: epoch), key)

        // Writing a different key for the same vault and epoch must report a conflict.
        XCTAssertThrowsError(try store.saveSyncKey(otherKey, vaultID: vaultID, epoch: epoch)) { error in
            XCTAssertEqual(error as? SyncKeyStoreError, .conflict)
        }

        let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
        XCTAssertEqual(deleteStatus, errSecSuccess)
        XCTAssertNil(try store.syncKey(vaultID: vaultID, epoch: epoch))
    }
}
