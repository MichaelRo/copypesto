// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("SensitiveContentDetector")
struct SensitiveContentDetectorTests {
    // MARK: - Credit cards

    @Test("detects a valid Visa-style credit card and masks all but last 4")
    func whenValidVisaCard_thenMaskWithLast4Visible() {
        // 4242 4242 4242 4242 — Stripe's well-known test card, passes Luhn.
        let result = SensitiveContentDetector.detect(in: "4242 4242 4242 4242")
        #expect(result?.category == .creditCard)
        #expect(result?.maskedPreview.hasSuffix("4242") == true)
        #expect(result?.maskedPreview.contains("•") == true)
        #expect(result?.maskedPreview.contains("4242 4242 4242") == false)
    }

    @Test("detects a valid Mastercard-style credit card")
    func whenValidMastercard_thenDetected() {
        let result = SensitiveContentDetector.detect(in: "5555555555554444")
        #expect(result?.category == .creditCard)
        #expect(result?.maskedPreview.hasSuffix("4444") == true)
    }

    @Test("ignores 16-digit numbers that fail Luhn")
    func whenLuhnFails_thenNotCreditCard() {
        let result = SensitiveContentDetector.detect(in: "1234567890123456")
        #expect(result?.category != .creditCard)
    }

    // MARK: - Card numbers inside longer text

    @Test("a card number inside a longer, multi-line copy is masked, and the preview hides the number", arguments: [
        "Name: A. Customer\nCard: 4242 4242 4242 4242\nExp 12/30  CVC 123",
        "Pay with 4242-4242-4242-4242 please, thanks",
        "card 5555555555554444 (work)",
        "Amex 3782 822463 10005, billing zip 94105"
    ])
    func whenCardNumberInsideText_thenMasked(text: String) {
        let result = SensitiveContentDetector.detect(in: text)
        #expect(result?.category == .creditCard)
        #expect(result?.maskedPreview.contains("•") == true)
        #expect(result?.maskedPreview.contains("4242 4242") == false)
        #expect(result?.maskedPreview.contains("5555") == false)
    }

    @Test("long digit runs that are not cards stay readable", arguments: [
        "Order 1700000000000 shipped from the warehouse on Friday",
        "Invoice 4111111111111112 is due next month (fails Luhn)",
        "tracking 12345678901234567890 for the parcel arriving soon",
        "Meeting notes: call 415 555 2671 or 650 555 0123 before noon",
        "Built 2026-10-02 2026-10-02 on the CI runner today"
    ])
    func whenDigitsAreNotACard_thenNotMasked(text: String) {
        #expect(SensitiveContentDetector.detect(in: text)?.category != .creditCard)
    }

    // MARK: - SSN

    @Test("detects US SSN format")
    func whenSSN_thenDetected() {
        let result = SensitiveContentDetector.detect(in: "123-45-6789")
        #expect(result?.category == .ssn)
        #expect(result?.maskedPreview.contains("•") == true)
    }

    @Test("does not match SSN with reserved prefixes (000, 666, 900-999)")
    func whenReservedSSNPrefix_thenNotSSN() {
        #expect(SensitiveContentDetector.detect(in: "000-45-6789")?.category != .ssn)
        #expect(SensitiveContentDetector.detect(in: "666-45-6789")?.category != .ssn)
        #expect(SensitiveContentDetector.detect(in: "900-45-6789")?.category != .ssn)
    }

    // MARK: - JWT

    @Test("detects JWT with eyJ header")
    func whenJWT_thenDetected() {
        let header = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
        let payload = "eyJzdWIiOiIxMjM0NTY3ODkwIn0"
        let sig = "SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        let jwt = "\(header).\(payload).\(sig)"
        let result = SensitiveContentDetector.detect(in: jwt)
        #expect(result?.category == .jwt)
    }

    // MARK: - OAuth tokens

    @Test("detects GitHub personal access token")
    func whenGitHubPAT_thenDetected() {
        let result = SensitiveContentDetector.detect(in: "ghp_abcdefghijklmnopqrstuvwxyz123456")
        #expect(result?.category == .oauthToken)
        #expect(result?.maskedPreview.contains("GitHub PAT") == true)
        #expect(result?.maskedPreview.contains("abcdef") == false)
    }

    @Test("detects the tokens of more services by their prefix", arguments: [
        ("glpat-abcdefghijklmnopqrstuvwx", "GitLab"),
        ("hf_abcdefghijklmnopqrstuvwxyzABCDEFGH", "Hugging Face"),
        ("npm_abcdefghijklmnopqrstuvwxyzABCDEFGHIJ", "npm"),
        ("xapp-1-A0123456789-0123456789-abcdef", "Slack App"),
        ("xoxs-1234567890-1234567890-abcdefghij", "Slack"),
        ("ya29.a0AfH6SMBabcdefghijklmnopqrstuvwxyz", "Google OAuth"),
        ("shpat_abcdefghijklmnopqrstuvwxyz012345", "Shopify"),
        ("dop_v1_abcdefghijklmnopqrstuvwxyz0123456789", "DigitalOcean"),
        ("lin_api_abcdefghijklmnopqrstuvwxyz0123456789", "Linear"),
        ("sk_test_abcdefghijklmnopqrstuvwx", "Stripe"),
        ("SG.abcdefghijklmnopqrstuv.abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG", "SendGrid")
    ])
    func whenAnotherServicesToken_thenMasked(token: String, label: String) {
        let result = SensitiveContentDetector.detect(in: token)

        #expect(result?.category == .oauthToken, "\(label)")
        #expect(result?.maskedPreview.contains("abcdefghij") == false, "\(label) showed its secret")
    }

    @Test("names that only start like those tokens are ordinary text")
    func whenAnEnvironmentVariableOrWord_thenNotMasked() {
        for text in [
            "npm_package_version",
            "hf_transformers_cache",
            "glpat-notes",
            "SG.Net",
            "ya29.5 percent",
            "dop_v1_docs"
        ] {
            #expect(SensitiveContentDetector.detect(in: text) == nil, "\(text)")
        }
    }

    @Test("detects Anthropic API key")
    func whenAnthropicAPIKey_thenDetected() {
        let result = SensitiveContentDetector.detect(in: "sk-ant-api03-fakekey1234567890fakekey1234567890")
        #expect(result?.category == .oauthToken)
        #expect(result?.maskedPreview.contains("Anthropic") == true)
    }

    @Test("Anthropic key is NOT misclassified as OpenAI — prefix order invariant")
    func whenAnthropicKey_thenLabelIsAnthropicNotOpenAI() {
        // "sk-ant-" starts with "sk-"; if oauthPrefixes were not sorted longest-first,
        // "sk-" would match first and label the key as "OpenAI API Key".
        let result = SensitiveContentDetector.detect(in: "sk-ant-api03-fakekey1234567890fakekey1234567890")
        #expect(result?.maskedPreview.contains("Anthropic") == true)
        #expect(result?.maskedPreview.contains("OpenAI") == false)
    }

    @Test("OpenAI project key is NOT misclassified as generic OpenAI key")
    func whenOpenAIProjectKey_thenLabelIsProjectKey() {
        let result = SensitiveContentDetector.detect(in: "sk-proj-fakekey1234567890fakekey1234567890")
        #expect(result?.maskedPreview.contains("Project") == true)
        #expect(result?.maskedPreview.contains("OpenAI API Key") == false)
    }

    @Test("detects OpenAI API key")
    func whenOpenAIAPIKey_thenDetected() {
        let result = SensitiveContentDetector.detect(in: "sk-fakekey1234567890fakekey1234567890")
        #expect(result?.category == .oauthToken)
        #expect(result?.maskedPreview.contains("OpenAI") == true)
    }

    @Test("detects Slack bot token")
    func whenSlackBotToken_thenDetected() {
        let result = SensitiveContentDetector.detect(in: "xoxb-12345-67890-abcdefghij")
        #expect(result?.category == .oauthToken)
    }

    @Test("detects AWS access key")
    func whenAWSAccessKey_thenDetected() {
        let result = SensitiveContentDetector.detect(in: "AKIAIOSFODNN7EXAMPLE")
        #expect(result?.category == .oauthToken)
    }

    // MARK: - Private key

    @Test("detects PEM-formatted private key")
    func whenPEMPrivateKey_thenDetected() {
        let pem = """
        -----BEGIN RSA PRIVATE KEY-----
        MIIEowIBAAKCAQEAxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
        -----END RSA PRIVATE KEY-----
        """
        let result = SensitiveContentDetector.detect(in: pem)
        #expect(result?.category == .privateKey)
    }

    // MARK: - Password

    @Test("detects password: prefix")
    func whenPasswordPrefix_thenDetected() {
        let result = SensitiveContentDetector.detect(in: "password: hunter2")
        #expect(result?.category == .password)
        #expect(result?.maskedPreview.contains("hunter2") == false)
    }

    @Test("detects bcrypt hash")
    func whenBcryptHash_thenDetected() {
        let result = SensitiveContentDetector.detect(in: "$2b$12$abcdefghijklmnopqrstuvwxyz0123456789ABCDEF")
        #expect(result?.category == .password)
    }

    // MARK: - High-entropy API keys

    @Test("detects high-entropy 40-char token without a known prefix")
    func whenHighEntropyToken_thenAPIKey() {
        // A randomly-generated 40-char alphanumeric token — high Shannon entropy.
        let result = SensitiveContentDetector.detect(in: "k3v9P2xLqR8nA7Fz1JbWmYsTcUe5Hg6XnMpZjQ4D")
        #expect(result?.category == .apiKey)
    }

    @Test("does NOT classify normal English prose as API key")
    func whenEnglishProse_thenNotAPIKey() {
        let result = SensitiveContentDetector
            .detect(in: "The quick brown fox jumps over the lazy dog and then takes a nap by the river side")
        #expect(result == nil)
    }

    @Test("does NOT classify a short hex string as API key")
    func whenShortHex_thenNotAPIKey() {
        let result = SensitiveContentDetector.detect(in: "deadbeef")
        #expect(result == nil)
    }

    // MARK: - Negative cases

    @Test("returns nil for empty string")
    func whenEmpty_thenNil() {
        #expect(SensitiveContentDetector.detect(in: "") == nil)
        #expect(SensitiveContentDetector.detect(in: "   \n\t   ") == nil)
    }

    @Test("returns nil for a normal sentence")
    func whenPlainText_thenNil() {
        #expect(SensitiveContentDetector.detect(in: "Hello world, how are you today?") == nil)
    }

    @Test("returns nil for a URL")
    func whenURL_thenNil() {
        #expect(SensitiveContentDetector.detect(in: "https://example.com/path?query=1") == nil)
    }

    // MARK: - Secrets inside longer text, such as OCR of a screenshot

    @Test("an API key inside a sentence is found")
    func detectAnywhere_findsAKeyInsideProse() {
        let text = "Set the variable ANTHROPIC to sk-ant-api03-EXAMPLEEXAMPLEEXAMPLEEXAMPLE1234567890abcdef and rerun."
        #expect(SensitiveContentDetector.detectAnywhere(in: text) != nil)
    }

    @Test("a key on its own line of a multi-line screenshot is found")
    func detectAnywhere_findsAKeyOnItsOwnLine() {
        let text = "terminal\n$ env\nsk-ant-api03-EXAMPLEEXAMPLEEXAMPLEEXAMPLE1234567890abcdef\n$ "
        #expect(SensitiveContentDetector.detectAnywhere(in: text)?.category == .oauthToken)
    }

    @Test("a card number on its own line is found")
    func detectAnywhere_findsACardOnItsOwnLine() {
        #expect(SensitiveContentDetector.detectAnywhere(in: "Payment\n4242 4242 4242 4242\nExp 12/30")?
            .category == .creditCard)
    }

    @Test("ordinary prose is not sensitive")
    func detectAnywhere_ignoresProse() {
        #expect(SensitiveContentDetector
            .detectAnywhere(in: "Team lunch is at 12:30 on Thursday, booked under Alex.") == nil)
        #expect(SensitiveContentDetector.detectAnywhere(in: "") == nil)
    }

    @Test("a whole-payload secret is still found the way it always was")
    func detectAnywhere_agreesWithDetectOnWholePayloads() {
        let key = "sk-ant-api03-EXAMPLEEXAMPLEEXAMPLEEXAMPLE1234567890abcdef"
        #expect(SensitiveContentDetector.detectAnywhere(in: key) == SensitiveContentDetector.detect(in: key))
    }

    // MARK: - Secrets inside larger text

    @Test("a password line further down a .env block is detected", arguments: [
        "DB_HOST=localhost\nDB_PASSWORD=hunter2hunter2\nDEBUG=true",
        "export AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        "api_key = \"abcd1234efgh5678ijkl\"",
        "GITHUB_TOKEN: ghx1234567890abcdef",
        "client_secret=Zm9vYmFyYmF6cXV4"
    ])
    func whenAssignmentLine_thenDetected(text: String) {
        #expect(SensitiveContentDetector.detect(in: text) != nil, "\(text)")
    }

    @Test("bearer tokens and vendor keys are detected wherever they appear in the text", arguments: [
        "curl -H 'Authorization: Bearer abcdEFGH1234ijklMNOP5678' https://example.com",
        "Authorization: Bearer abcdEFGH1234ijklMNOP5678",
        "use sk_live_51HabcdEFGH1234ijklMNOP here",
        "key is AIzaSyA1234567890abcdefghijklmnopqrstuv ok"
    ])
    func whenTokenInText_thenDetected(text: String) {
        #expect(SensitiveContentDetector.detect(in: text) != nil, "\(text)")
    }

    @Test("ordinary text that mentions passwords or tokens is not flagged", arguments: [
        "The password policy is documented on the wiki.",
        "token count: 5",
        "secret santa: December 5th at the office",
        "commit 3f2a9c1b7d4e5a6f8b9c0d1e2f3a4b5c6d7e8f90 fixes the crash",
        "Reset your password by clicking the link in the email."
    ])
    func whenOrdinaryText_thenNotFlagged(text: String) {
        #expect(SensitiveContentDetector.detect(in: text) == nil, "\(text)")
    }

    @Test("multi-line markdown text containing a password reference is not classified as credential")
    func whenMultiLineMarkdownContainsPasswordReference_thenNotClassifiedAsCredential() {
        let markdown = """
        # Deployment Guide

        To deploy the application to the staging server, follow these steps:

        1. Pull the latest image from the registry.
        2. Set up the environment variables according to the sample file.
        3. Enter the default administrator credentials on first launch:

        Username: admin
        Password: change-on-first-login

        Ensure all firewall ports are properly configured before opening traffic.
        """
        let result = SensitiveContentDetector.detect(in: markdown)
        #expect(result == nil)
    }

    // MARK: - Large text (the 50,000-byte ReDoS guard must not leave a big copy unmasked)

    private static let prose = String(repeating: "The quarterly numbers are on the shared drive.\n", count: 10_000)

    @Test("a token deep inside a copy larger than 50 KB is still found")
    func whenLargeTextHoldsAToken_thenDetected() {
        let text = Self.prose + "GITHUB_TOKEN=ghp_abcdefghijklmnopqrstuvwxyz123456\n" + Self.prose
        #expect(text.utf8.count > 900_000)
        #expect(SensitiveContentDetector.detect(in: text) != nil)
    }

    @Test("a secret inside a single huge line is found when it is not cut by a window boundary")
    func whenOneHugeLineHoldsAToken_thenDetected() {
        let filler = String(repeating: "lorem ipsum dolor sit amet ", count: 4000)
        let text = filler + " Authorization: Bearer abcdefghijklmnopqrstuvwxyz123456 " + filler
        #expect(text.utf8.count > 200_000)
        #expect(SensitiveContentDetector.detect(in: text) != nil)
    }

    @Test("large text with no secret is not flagged, and scanning it stays cheap")
    func whenLargeTextHasNoSecret_thenNilWithinTheBudget() {
        let text = Self.prose + Self.prose + Self.prose
        let start = ContinuousClock.now
        let result = SensitiveContentDetector.detect(in: text)
        let elapsed = ContinuousClock.now - start
        #expect(result == nil)
        #expect(elapsed < .seconds(10), "scanning \(text.utf8.count) bytes took \(elapsed)")
    }

    @Test("a secret at the very end of the largest text Pesto keeps is still found")
    func whenTheSecretIsAtTheEndOfTheLargestCopy_thenFound() {
        let line = "The quarterly numbers are on the shared drive.\n"
        let lines = (ClipSizePolicy.maxTextBytes - 100) / line.utf8.count
        let text = String(repeating: line, count: lines) + "GITHUB_TOKEN=ghp_abcdefghijklmnopqrstuvwxyz123456\n"
        #expect(text.utf8.count < ClipSizePolicy.maxTextBytes)
        #expect(text.utf8.count > 2_000_000, "the secret must sit past the old 2 MB cap")
        #expect(SensitiveContentDetector.detect(in: text) != nil)
    }

    @Test("the scan covers everything a copy may hold, so no accepted copy has an unscanned tail")
    func whenTheScanCapIsRead_thenItIsTheTextLimit() {
        #expect(SensitiveContentDetector.maxScannedBytes >= ClipSizePolicy.maxTextBytes)
    }

    // MARK: - Prefixes need a token, not a sentence

    @Test("ordinary text that starts like a key prefix is not masked")
    func whenProseStartsWithAKeyPrefix_thenNotSensitive() {
        #expect(SensitiveContentDetector.detect(in: "ASIAN GAMES 2026 schedule") == nil)
        #expect(SensitiveContentDetector.detect(in: "AKIAN is a company name in this list") == nil)
        #expect(SensitiveContentDetector.detect(in: "sk-learn is a Python library for machine learning") == nil)
    }

    @Test("an AWS key is the prefix and exactly sixteen more capitals or digits")
    func whenAnAWSKey_thenDetected() {
        #expect(SensitiveContentDetector.detect(in: "ASIAIOSFODNN7EXAMPLE")?.category == .oauthToken)
        #expect(SensitiveContentDetector.detect(in: "AKIAIOSFODNN7EXAMPLE")?.category == .oauthToken)
        #expect(SensitiveContentDetector.detect(in: "AKIAIOSFODNN7EXAMPLEXTRA") == nil)
    }

    @Test("every built-in pattern compiles, so a typo cannot quietly turn a detector off")
    func whenLoaded_thenEveryPatternCompiled() {
        #expect(SensitiveContentDetector.compiledPatternCount == 10)
    }

    @Test("localizedMask returns descriptive mask text for each category")
    func whenLocalizedMaskRequested_thenMaskProvided() {
        for category in SensitivityCategory.allCases {
            let mask = SensitiveContentDetector.localizedMask(for: category, count: 32)
            #expect(!mask.isEmpty)
        }
    }
}
