// SPDX-License-Identifier: MIT
import Foundation
import Security
import Testing
@testable import PestoCore

@Suite("DeviceIdentity")
struct DeviceIdentityTests {
    /// Runs `body` with an identity in its own Keychain namespace and deletes whatever it stored, so a test run leaves
    /// nothing in the login Keychain.
    private func withIdentity<T>(_ body: (DeviceIdentity) throws -> T) rethrows -> T {
        let tag = UUID().uuidString
        let identity = DeviceIdentity(
            service: "io.pesto.app.tests.\(tag)",
            account: "io.pesto.app.tests.deviceID.\(tag)"
        )
        defer { Self.delete(identity) }
        return try body(identity)
    }

    private static func delete(_ identity: DeviceIdentity) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: identity.service,
            kSecAttrAccount as String: identity.account
        ] as CFDictionary)
    }

    private static func exists(_ identity: DeviceIdentity) -> Bool {
        SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: identity.service,
            kSecAttrAccount as String: identity.account
        ] as CFDictionary, nil) == errSecSuccess
    }

    @Test("a test's identity is removed from the Keychain when it is done")
    func whenTheTestEnds_thenNothingIsLeftInTheKeychain() throws {
        var used: DeviceIdentity?
        try withIdentity { identity in
            _ = try identity.loadOrCreate()
            #expect(Self.exists(identity))
            used = identity
        }
        #expect(try !Self.exists(#require(used)))
    }

    @Test("whenCalledTwice_thenReturnsSameID")
    func whenCalledTwice_thenReturnsSameID() throws {
        try withIdentity { identity in
            let first = try identity.loadOrCreate()
            let second = try identity.loadOrCreate()
            #expect(first == second)
        }
    }

    @Test("whenIDExists_thenReturnsValidUUID")
    func whenIDExists_thenReturnsValidUUID() throws {
        try withIdentity { identity in
            let id = try identity.loadOrCreate()
            #expect(UUID(uuidString: id) != nil)
        }
    }

    @Test("whenIDExists_thenIsRFC4122Format")
    func whenIDExists_thenIsRFC4122Format() throws {
        try withIdentity { identity in
            let id = try identity.loadOrCreate()
            // UUID strings are 36 chars: 8-4-4-4-12 hex digits separated by hyphens,
            // uppercased by UUID.uuidString.
            let pattern = #"^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$"#
            #expect(id.range(of: pattern, options: .regularExpression) != nil)
        }
    }

    @Test("an unreadable item in the way is an error, not an identity that was never stored")
    func whenAnUnreadableItemBlocksTheWrite_thenThrows() {
        withIdentity { identity in
            let blocker: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: identity.service,
                kSecAttrAccount as String: identity.account,
                kSecValueData as String: Data([0xFF, 0xFE, 0xFD])
            ]
            #expect(SecItemAdd(blocker as CFDictionary, nil) == errSecSuccess)

            #expect(throws: BlobEncryption.Error.self) { try identity.loadOrCreate() }
        }
    }

    @Test("under a test launch the identity is the session's and the login Keychain is never read")
    func whenNotTheApp_thenTheSessionsIdentityAndNoKeychain() {
        let configuration = RuntimeConfiguration(mode: .uiTest, session: "abc", seed: .empty, accessibility: .trusted)
        let untouched = DeviceIdentity(service: "io.pesto.app.tests.\(UUID())", account: "never-created")

        #expect(DeviceIdentity.current(configuration: configuration, identity: untouched) == "uitest-device-abc")
        #expect(!Self.exists(untouched), "a test launch must not create a Keychain item")
    }
}
