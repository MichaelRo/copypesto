// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Identifiers are not API keys, and non-card numbers stay readable")
struct IdentifierShapeTests {
    @Test("an AWS account name made of words and an account number is not an API key")
    func whenKebabCaseAccountName_thenNotAPIKey() {
        #expect(SensitiveContentDetector.detect(in: "gov3-auto-aws-admin-aft-267952938337") == nil)
    }

    @Test(
        "names that people copy all day are not secrets",
        arguments: [
            "prod-eu-west-1-payments-ledger-writer-role",
            "prod2-us1-east1-ecs1-db2-admin1-aft-267952938337",
            "arn:aws:iam::267952938337:role/gov3-auto-aws-admin-aft",
            "550e8400-e29b-41d4-a716-446655440000",
            "9fceb02d0ae598e95dc970b74767f19372d61af8",
            "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
            "my-company-terraform-state-bucket-eu-central-1",
            "com.example.application.feature.settings.pane",
            "docker.io/library/postgres-with-extensions-and-more",
            "feature_branch_update_onboarding_defaults_2026",
            "SomeVeryLongPascalCaseTypeNameForAThingThatExists",
            "serviceV2ProductionEndpointHandlerFactory",
            "12345678901234567890123456789012345",
            "release-candidate-2026-11-11-build-48210-final",
            "s3://my-company-prod-analytics-exports-eu-west-1",
            "arn-aws-s3-prod-analytics-exports-eu-west-1-2026",
            "customer_support_ticket_export_2026_11_11_final",
            "prod-eu-west-1-authentication-configuration-service",
            "SCREAMING_SNAKE_CONFIGURATION_SERVICE",
            "01234567-89ab-4cde-8f01-23456789abcd"
        ]
    )
    func whenIdentifier_thenNotASecret(_ text: String) {
        #expect(SensitiveContentDetector.detect(in: text) == nil, "\(text)")
    }

    @Test(
        "keys with no vendor prefix, prefixed custom keys, and digit-free keys are still found",
        arguments: [
            "k3v9P2xLqR8nA7Fz1JbWmYsTcUe5Hg6XnMpZjQ4D",
            "aB3dE7fG9hJ2kL5mN8pQ1rS4tU6vW0xYzA3bC5dE",
            "q7Zx-2Lm9_Pw4Rt8Vb1Kc6Yn3Hd5Jf0GsA2uXeO9iT",
            "Zm9vYmFyMTIzNDU2Nzg5MGFiY2RlZkdISUpLTE1OTw",
            "x7k2m9q4-p8r3t6v1-w5y2z7a4-b9c3d6e1-zq8",
            "Kj82-mQ9x_LpR4tVb6Yn3Hd5Jf0GsA2uXeO9iT7w",
            "acme-prod-api-k3v9P2xLqR8nA7Fz1JbWmYsTcUe5Hg6X",
            "acme-prod-api-k3v9P2xL-qR8nA7Fz1",
            "acme_token_9xK2mP7qL_vL4nR8wZb5c",
            "service-account-XKQAVBMNPOWERDFZ",
            "service-account-xkqavbmnpowerdfz",
            "my_vendor_key_A8kLm2PqR7vXw9Yz0BcDeFgH",
            "xKqPmZvLtRnWbYcJhGfDsAcVbNmPqRsTuVwXyZ"
        ]
    )
    func whenRandomLookingToken_thenAPIKey(_ text: String) {
        #expect(SensitiveContentDetector.detect(in: text)?.category == .apiKey, "\(text)")
    }

    @Test(
        "hyphenated dates, resource IDs, and ticket numbers containing 3-2-4 digits are not SSNs",
        arguments: [
            "subnet-123-45-6789-prod",
            "2026-123-45-6789",
            "123-45-6789-0123",
            "ticket-987-65-4321-closed"
        ]
    )
    func whenHyphenatedNumber_thenNotSSN(_ text: String) {
        #expect(SensitiveContentDetector.detect(in: text) == nil, "\(text)")
    }

    @Test("a real SSN inside punctuation or prose is still masked", arguments: [
        "123-45-6789",
        "SSN: 123-45-6789",
        "ssn=123-45-6789",
        "(123-45-6789)"
    ])
    func whenRealSSN_thenMasked(_ text: String) {
        #expect(SensitiveContentDetector.detect(in: text)?.category == .ssn, "\(text)")
    }

    @Test(
        "standalone Luhn-valid numbers without a card issuer prefix are not credit cards",
        arguments: [
            "1731280000000",
            "9876543210123452",
            "0000 0000 0000 0000"
        ]
    )
    func whenLuhnValidNonIssuerNumber_thenNotCreditCard(_ text: String) {
        #expect(SensitiveContentDetector.detect(in: text) == nil, "\(text)")
    }

    @Test("a token under 32 characters is never a generic key, however random")
    func whenShortToken_thenNotAPIKey() {
        #expect(SensitiveContentDetector.detect(in: "k3v9P2xLqR8nA7Fz1JbWmYsTcUe5Hg6") == nil)
    }

    @Test("a name with spaces around a key-like word is prose, not a key")
    func whenSentenceMentionsAName_thenNil() {
        #expect(SensitiveContentDetector.detect(in: "use gov3-auto-aws-admin-aft-267952938337 for the audit") == nil)
    }

    @Test("a vendor-prefixed key is still found when its body looks like words")
    func whenPrefixedKey_thenStillDetected() {
        #expect(SensitiveContentDetector.detect(in: "sk-ant-api03-Zk8Qm2Lp9Xr4Tv6Yb1Nc3Hd5Jf0Gs")?
            .category == .oauthToken)
    }
}
