// SPDX-License-Identifier: MIT
import Foundation
import Security

/// Earlier builds could store a Claude, ChatGPT or Gemini key in the Keychain. Pesto no longer talks to any of them,
/// so those keys are deleted rather than left behind.
public enum LegacyAIKeyCleanup {
    public struct Locations: Sendable {
        let singleService: String
        let singleAccount: String
        let perProviderService: String
        let providerAccounts: [String]

        public static let standard = Locations(
            singleService: "io.pesto.app", singleAccount: "anthropic-api-key",
            perProviderService: "io.pesto.app.ai", providerAccounts: ["claude", "openai", "gemini", "apple"]
        )
    }

    public static func run(_ locations: Locations = .standard) {
        remove(service: locations.singleService, account: locations.singleAccount)
        for account in locations.providerAccounts {
            remove(service: locations.perProviderService, account: account)
        }
    }

    private static func remove(service: String, account: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ] as CFDictionary)
    }
}
