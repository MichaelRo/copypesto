// SPDX-License-Identifier: MIT
import Foundation

public enum SensitivityCategory: String, Codable, Sendable, CaseIterable {
    case creditCard = "credit_card"
    case ssn
    case jwt
    case apiKey = "api_key"
    case oauthToken = "oauth_token"
    case privateKey = "private_key"
    case password
    case credential
}

public extension SensitivityCategory {
    /// What a person types to find a hidden clip of this kind. The card shows dots, so the kind is the only thing to
    /// search.
    var searchName: String {
        switch self {
        case .creditCard: String(localized: "Card")
        case .ssn: "SSN"
        case .jwt: "JWT"
        case .apiKey: String(localized: "API key")
        case .oauthToken: String(localized: "Token") + " OAuth"
        case .privateKey: String(localized: "Private key")
        case .password: String(localized: "Password")
        case .credential: String(localized: "Credential")
        }
    }
}

public extension SensitivityCategory {
    /// The word on a hidden card's badge. A token covers API keys and personal access tokens as well as OAuth grants,
    /// so it says what a person would call it, not the protocol.
    var badgeLabel: String {
        switch self {
        case .creditCard: "Card"
        case .ssn: "SSN"
        case .jwt: "JWT"
        case .apiKey: "API Key"
        case .oauthToken: "Token"
        case .privateKey: "Private Key"
        case .password: "Password"
        case .credential: "Credential"
        }
    }
}
