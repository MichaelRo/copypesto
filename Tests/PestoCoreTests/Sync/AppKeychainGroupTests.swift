// SPDX-License-Identifier: MIT
import Foundation
import Security
import Testing
@testable import PestoCore

@Suite("The app's own Keychain items are asked for in the app's own group on iOS, and as before on the Mac")
struct AppKeychainGroupTests {
    private let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: AppIdentity.keychainService,
        kSecAttrAccount as String: AppIdentity.blobKeyAccount
    ]

    @Test("a query pinned to a group names that group and keeps everything else")
    func whenPinnedToAGroup_thenTheGroupIsNamed() {
        let pinned = AppKeychainGroup.pinned(query, to: "TEAMID.net.copypesto.pesto")
        #expect(pinned[kSecAttrAccessGroup as String] as? String == "TEAMID.net.copypesto.pesto")
        #expect(Set(pinned.keys) == Set(query.keys).union([kSecAttrAccessGroup as String]))
        #expect(pinned[kSecAttrAccount as String] as? String == AppIdentity.blobKeyAccount)
    }

    @Test("with no group the query is left exactly as it was")
    func whenThereIsNoGroup_thenTheQueryIsUnchanged() {
        let unpinned = AppKeychainGroup.pinned(query, to: nil)
        #expect(Set(unpinned.keys) == Set(query.keys))
        #expect(unpinned[kSecAttrAccessGroup as String] == nil)
    }

    @Test("the own group is the prefix and the bundle ID; no prefix, no group")
    func whenThePrefixIsKnown_thenTheOwnGroupIsTheApps() {
        #expect(AppKeychainGroup.ownGroup(prefix: "ABCDE12345.") == "ABCDE12345." + AppIdentity.bundleID)
        #expect(AppKeychainGroup.ownGroup(prefix: "") == nil)
        #expect(AppKeychainGroup.ownGroup(prefix: nil) == nil)
    }

    @Test("on the Mac nothing is pinned, so no existing Mac item is looked up anew; on iOS the app's group is")
    func whenOnThisPlatform_thenTheOwnGroupIsRight() {
        #if os(macOS)
        #expect(AppKeychainGroup.own == nil)
        #expect(AppKeychainGroup.pinned(query)[kSecAttrAccessGroup as String] == nil)
        #else
        let prefix = Bundle.main.object(forInfoDictionaryKey: AppIdentity.appIdentifierPrefixInfoKey) as? String
        #expect(AppKeychainGroup.own == AppKeychainGroup.ownGroup(prefix: prefix))
        #endif
    }

    @Test("the iCloud sync key's query is pinned like the others")
    func whenTheSyncKeyIsAskedFor_thenItsQueryIsPinned() {
        let base = ICloudSyncKeyStore().baseQuery(vaultID: Data(repeating: 1, count: 16), epoch: 1)
        #expect(base[kSecAttrAccessGroup as String] as? String == AppKeychainGroup.own)
    }
}
