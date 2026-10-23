// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import Testing
@testable import PestoCore

@Suite("Isolated encryption key")
struct IsolatedKeyTests {
    private func configuration(mode: LaunchMode, session: String = "default") -> RuntimeConfiguration {
        RuntimeConfiguration(mode: mode, session: session, seed: .basic, accessibility: .trusted)
    }

    private func bytes(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    @Test("a normal launch has no isolated key, so the Keychain key is used")
    func whenNormal_thenNoIsolatedKey() {
        #expect(BlobEncryption.isolatedKey(for: configuration(mode: .normal)) == nil)
    }

    @Test("test launches get a 256-bit key that never touches the Keychain")
    func whenNotNormal_thenIsolatedKey() throws {
        for mode in [LaunchMode.uiTest, .hostedTests] {
            let key = try #require(BlobEncryption.isolatedKey(for: configuration(mode: mode)))
            #expect(key.bitCount == 256)
        }
    }

    @Test("the same session always derives the same key, so data survives an app relaunch")
    func whenSameSession_thenSameKey() throws {
        let first = try #require(BlobEncryption.isolatedKey(for: configuration(mode: .uiTest, session: "run-1")))
        let second = try #require(BlobEncryption.isolatedKey(for: configuration(mode: .uiTest, session: "run-1")))
        #expect(bytes(first) == bytes(second))
    }

    @Test("different sessions derive different keys")
    func whenDifferentSessions_thenDifferentKeys() throws {
        let first = try #require(BlobEncryption.isolatedKey(for: configuration(mode: .uiTest, session: "run-1")))
        let second = try #require(BlobEncryption.isolatedKey(for: configuration(mode: .uiTest, session: "run-2")))
        #expect(bytes(first) != bytes(second))
    }
}
