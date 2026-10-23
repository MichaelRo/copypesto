// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import Testing
@testable import Pesto

/// Regression: hosted tests ran StorageService against the user's real Keychain
/// key. In a hosted run BlobEncryption must use the in-memory key and create no Keychain item.
@Suite("Hosted Keychain isolation")
struct HostedKeychainIsolationTests {
    @Test("encrypting in a hosted test run never creates a Keychain item")
    func whenEncryptingInHostedRun_thenNoKeychainItem() throws {
        let service = "io.pesto.tests.hosted-key.\(UUID().uuidString)"
        let account = "isolation"
        let encryption = BlobEncryption(keychainService: service, keychainAccount: account)

        let envelope = try encryption.encrypt(Data("secret".utf8))

        #expect(try encryption.decrypt(envelope) == Data("secret".utf8))
        #expect(!BlobEncryption.keyExists(service: service, account: account))
    }
}
