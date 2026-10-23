// SPDX-License-Identifier: MIT
import Foundation
import Security
import Testing
@testable import PestoCore

@Suite("Legacy AI key cleanup")
struct LegacyAIKeyCleanupTests {
    private func add(service: String, account: String) {
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data("secret".utf8)
        ]
        SecItemDelete(attrs as CFDictionary)
        #expect(SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess, "could not write the fixture item")
    }

    private func remove(service: String, account: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account
        ] as CFDictionary)
    }

    private func exists(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    @Test("saved provider keys are removed, and other Keychain items are left alone")
    func whenRun_thenOnlyLegacyItemsGo() {
        let tag = UUID().uuidString
        let legacy = LegacyAIKeyCleanup.Locations(
            singleService: "io.pesto.tests.legacy.\(tag)", singleAccount: "anthropic-api-key",
            perProviderService: "io.pesto.tests.legacy.ai.\(tag)", providerAccounts: ["claude", "openai", "gemini"]
        )
        add(service: legacy.singleService, account: legacy.singleAccount)
        add(service: legacy.perProviderService, account: "claude")
        add(service: legacy.perProviderService, account: "gemini")
        add(service: legacy.singleService, account: "unrelated")
        defer {
            remove(service: legacy.singleService, account: legacy.singleAccount)
            remove(service: legacy.singleService, account: "unrelated")
            for account in ["claude", "gemini"] {
                remove(service: legacy.perProviderService, account: account)
            }
        }

        LegacyAIKeyCleanup.run(legacy)

        #expect(!exists(service: legacy.singleService, account: legacy.singleAccount))
        #expect(!exists(service: legacy.perProviderService, account: "claude"))
        #expect(!exists(service: legacy.perProviderService, account: "gemini"))
        #expect(exists(service: legacy.singleService, account: "unrelated"))
    }

    @Test("running twice is harmless")
    func whenNothingThere_thenNoError() {
        let legacy = LegacyAIKeyCleanup.Locations(
            singleService: "io.pesto.tests.none.\(UUID().uuidString)", singleAccount: "a",
            perProviderService: "io.pesto.tests.none.ai.\(UUID().uuidString)", providerAccounts: ["claude"]
        )
        LegacyAIKeyCleanup.run(legacy)
        LegacyAIKeyCleanup.run(legacy)
    }
}
