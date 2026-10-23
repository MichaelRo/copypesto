// SPDX-License-Identifier: MIT
import Foundation

/// Detects sensitive content in clipboard previews. See ADR 0003.
///
/// Runs at ingest time on the candidate `previewText`. If a match is found we set
/// `sensitivityRaw` and replace the rendered preview with a masked form. The full
/// payload still lives encrypted in `ClipboardBlob` — masking is a UI-side privacy
/// feature, not an exfiltration block.
public enum SensitiveContentDetector {
    public struct Result: Sendable, Equatable {
        public let category: SensitivityCategory
        public let maskedPreview: String

        public init(category: SensitivityCategory, maskedPreview: String) {
            self.category = category
            self.maskedPreview = maskedPreview
        }
    }

    /// The most text one regex pass sees: past this, pathological input can make the patterns run for a very long time.
    public static let maxWindowBytes = 50_000

    /// The most text of one copy that is scanned. A larger copy is scanned up to here and no further, so the cost of
    /// one copy stays bounded; a secret beyond it is not masked.
    public static let maxScannedBytes = ClipSizePolicy.maxTextBytes

    /// Inspect the payload string. Returns a `Result` when sensitive, nil otherwise.
    /// The first matching category wins — order is most-specific first.
    ///
    /// Text larger than `maxWindowBytes` is scanned in windows of whole lines (see `maxScannedBytes`): each pass
    /// still sees at most 50 KB, which is what keeps the patterns from running away on pathological input.
    public static func detect(in payload: String) -> Result? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Use utf8.count (bytes), not count (Unicode scalars) — emoji-dense strings pass the
        // scalar guard while exceeding 50 KB in memory and slowing regex matching.
        guard trimmed.utf8.count <= maxWindowBytes else { return detectInWindows(of: trimmed) }
        return match(in: trimmed)
    }

    private static func match(in trimmed: String) -> Result? {
        if let cc = creditCardMatch(trimmed) ?? embeddedCardMatch(trimmed) { return cc }
        if let priv = privateKeyMatch(trimmed) { return priv }
        if let jwt = jwtMatch(trimmed) { return jwt }
        if let oauth = oauthTokenMatch(trimmed) { return oauth }
        if let ssn = ssnMatch(trimmed) { return ssn }
        if !isStructuredDocumentOrMarkdown(trimmed) {
            if let pw = passwordLineMatch(trimmed) { return pw }
            if let assigned = secretAssignmentMatch(trimmed) { return assigned }
        }
        if let embedded = embeddedTokenMatch(trimmed) { return embedded }
        if let key = apiKeyMatch(trimmed) { return key }

        return nil
    }

    private static func isStructuredDocumentOrMarkdown(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count >= 3 else { return false }

        let totalWords = text.split(whereSeparator: \.isWhitespace).count
        guard totalWords >= 20 else { return false }

        let hasHeading = text.range(of: #"(?m)^#{1,6}\s+\S+"#, options: .regularExpression) != nil
        if hasHeading { return true }

        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if paragraphs.count >= 2 {
            let proseParagraphs = paragraphs.filter { para in
                para.split(whereSeparator: \.isWhitespace).count >= 6 &&
                    (para.contains(".") || para.contains(","))
            }
            if proseParagraphs.count >= 2 { return true }
        }

        return false
    }

    private static func detectInWindows(of text: String) -> Result? {
        let head = text.prefix(maxScannedBytes + maxWindowBytes)
        var window = ""
        var windowBytes = 0
        var scanned = 0
        for line in head.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            for piece in pieces(of: line) {
                let bytes = piece.utf8.count + 1
                if windowBytes + bytes > maxWindowBytes, !window.isEmpty {
                    if let found = scan(window) { return found }
                    scanned += windowBytes
                    if scanned >= maxScannedBytes { return nil }
                    window = ""
                    windowBytes = 0
                }
                window += piece + "\n"
                windowBytes += bytes
            }
        }
        return scan(window)
    }

    private static func scan(_ window: String) -> Result? {
        let trimmed = window.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= maxWindowBytes else { return nil }
        return match(in: trimmed)
    }

    /// A line longer than a window (minified JSON, base64) is cut into pieces that fit one.
    private static func pieces(of line: Substring) -> [String] {
        guard line.utf8.count > maxWindowBytes else { return [String(line)] }
        let size = 10_000
        var result: [String] = []
        var start = line.startIndex
        while start < line.endIndex {
            let end = line.index(start, offsetBy: size, limitedBy: line.endIndex) ?? line.endIndex
            result.append(String(line[start..<end]))
            start = end
        }
        return result
    }

    /// Like `detect`, but for text that merely *contains* a secret, such as OCR of a screenshot: tries the whole
    /// text, then each line, then each whitespace-separated word.
    public static func detectAnywhere(in text: String) -> Result? {
        if let whole = detect(in: text) { return whole }
        guard text.utf8.count <= 50_000 else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            if let found = detect(in: String(line)) { return found }
        }
        for word in text.split(whereSeparator: \.isWhitespace) where word.count >= 8 {
            if let found = detect(in: String(word)) { return found }
        }
        return nil
    }

    // MARK: - Patterns

    /// Built once: `detectAnywhere` runs these over every word of OCR text, and a pattern compiled per call was both
    /// slow
    /// and, through `try?`, silent when it failed, which would have switched a detector off without a sign.
    private enum Patterns {
        static let creditCard = compile(#"\b(?:\d[ -]?){12,18}\d\b"#)
        static let embeddedCard = compile(#"(?<![0-9])[0-9](?:[ -]?[0-9]){12,18}(?![0-9])"#)
        static let ssn = compile(#"\b(?!000|666|9\d{2})\d{3}-(?!00)\d{2}-(?!0000)\d{4}\b"#)
        static let jwt = compile(#"^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$"#)
        static let passwordLine = compile(
            #"(?im)^\s*(?:export\s+)?(?:[a-z0-9_.-]*[_.-])?(password|passwd|pwd)\s*[:=]\s*\S+"#
        )
        static let secretAssignment = compile(
            "(?im)^\\s*(?:export\\s+)?[a-z0-9_.-]*(?:secret|token|api[_-]?key|apikey|access[_-]?key|private[_-]?key)"
                + "\\s*[:=]\\s*[\"']?[^\\s\"']{6,}"
        )
        static let awsKey = compile(#"^(?:AKIA|ASIA)[A-Z0-9]{16}$"#)
        static let embeddedTokens = [
            compile(#"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{16,}"#),
            compile(#"\b(?:sk|rk)_live_[A-Za-z0-9]{16,}"#),
            compile(#"\bAIza[A-Za-z0-9_-]{30,}"#)
        ]

        static var all: [NSRegularExpression] {
            [creditCard, embeddedCard, ssn, jwt, passwordLine, secretAssignment, awsKey] + embeddedTokens
        }

        private static func compile(_ pattern: String) -> NSRegularExpression {
            do {
                return try NSRegularExpression(pattern: pattern)
            } catch {
                preconditionFailure("built-in secret pattern does not compile: \(pattern)")
            }
        }
    }

    /// How many built-in patterns exist and compiled; a test pins it.
    static var compiledPatternCount: Int {
        Patterns.all.count
    }

    // MARK: - Credit card (Luhn-validated)

    private static func creditCardMatch(_ text: String) -> Result? {
        // Credit card numbers are 13–26 chars including spaces/dashes; no need to run regex on longer text.
        guard text.count >= 13, text.count <= 26 else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = Patterns.creditCard.firstMatch(in: text, range: range),
              let r = Range(match.range, in: text) else { return nil }
        let raw = text[r].filter(\.isNumber)
        guard raw.count >= 13, raw.count <= 19 else { return nil }
        guard luhnValid(raw) else { return nil }

        let last4 = String(raw.suffix(4))
        let groups = max(0, raw.count - 4)
        let bullets = String(repeating: "•", count: groups)
        let masked = formatCard(bullets + last4)
        return Result(category: .creditCard, maskedPreview: masked)
    }

    /// A card number anywhere in longer text (an order form, a copied email). Prose is full of long digit runs, so a
    /// candidate must be 13 to 19 digits that nothing else touches, pass Luhn and start like a real issuer's number.
    private static func embeddedCardMatch(_ text: String) -> Result? {
        guard text.count > 26 else { return nil }
        for match in Patterns.embeddedCard.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let r = Range(match.range, in: text) else { continue }
            let digits = String(text[r].filter(\.isNumber))
            guard (13...19).contains(digits.count), luhnValid(digits), hasIssuerPrefix(digits) else { continue }
            return Result(category: .creditCard, maskedPreview: "•••• •••• •••• \(digits.suffix(4))")
        }
        return nil
    }

    private static func hasIssuerPrefix(_ digits: String) -> Bool {
        let first = digits.prefix(1)
        let two = Int(digits.prefix(2)) ?? 0
        let four = Int(digits.prefix(4)) ?? 0
        if first == "4" { return [13, 16, 19].contains(digits.count) }
        if (51...55).contains(two) || (2221...2720).contains(four) { return digits.count == 16 }
        if two == 34 || two == 37 { return digits.count == 15 }
        if four == 6011 || two == 65 || (644...649).contains(Int(digits.prefix(3)) ?? 0) { return digits.count >= 16 }
        if two == 36 || two == 38 || (300...305)
            .contains(Int(digits.prefix(3)) ?? 0) { return (14...16).contains(digits.count) }
        if (3528...3589).contains(four) { return digits.count >= 16 }
        if two == 62 { return digits.count >= 16 }
        return false
    }

    private static func luhnValid(_ digits: String) -> Bool {
        var sum = 0
        for (i, char) in digits.reversed().enumerated() {
            guard let d = char.wholeNumberValue else { return false }
            if i.isMultiple(of: 2) {
                sum += d
            } else {
                let doubled = d * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            }
        }
        return sum.isMultiple(of: 10)
    }

    private static func formatCard(_ s: String) -> String {
        // Group in 4s for legibility: "••••••••••••4242" → "•••• •••• •••• 4242"
        var out = ""
        for (i, c) in s.enumerated() {
            if i > 0, i.isMultiple(of: 4) { out.append(" ") }
            out.append(c)
        }
        return out
    }

    // MARK: - SSN

    private static func ssnMatch(_ text: String) -> Result? {
        guard Patterns.ssn.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil else {
            return nil
        }
        return Result(category: .ssn, maskedPreview: "•••-••-••••")
    }

    // MARK: - JWT

    private static func jwtMatch(_ text: String) -> Result? {
        guard Patterns.jwt.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil else {
            return nil
        }
        return Result(category: .jwt, maskedPreview: hiddenCountMask(text.count))
    }

    // MARK: - OAuth tokens with known prefixes

    /// Sorted longest-prefix-first so more-specific entries match before shorter ones
    /// (e.g. "sk-ant-" must precede "sk-proj-" which must precede "sk-").
    private struct TokenPrefix {
        let prefix: String
        let label: String
        let minimumTail: Int

        init(_ prefix: String, _ label: String, _ minimumTail: Int) {
            self.prefix = prefix
            self.label = label
            self.minimumTail = minimumTail
        }
    }

    private static let oauthPrefixes: [TokenPrefix] = [
        TokenPrefix("github_pat_", "GitHub Fine-Grained PAT", 10),
        TokenPrefix("sk-ant-api", "Anthropic API Key", 10),
        TokenPrefix("sk-ant-", "Anthropic API Key", 10),
        TokenPrefix("sk-proj-", "OpenAI Project Key", 10),
        TokenPrefix("xoxb-", "Slack Bot Token", 10),
        TokenPrefix("xoxp-", "Slack User Token", 10),
        TokenPrefix("xoxs-", "Slack Token", 10),
        TokenPrefix("xoxa-", "Slack Token", 10),
        TokenPrefix("xoxr-", "Slack Token", 10),
        TokenPrefix("xapp-", "Slack App Token", 20),
        TokenPrefix("ghp_", "GitHub PAT", 10),
        TokenPrefix("gho_", "GitHub OAuth", 10),
        TokenPrefix("ghs_", "GitHub Server", 10),
        TokenPrefix("ghu_", "GitHub User Token", 10),
        TokenPrefix("ghr_", "GitHub Refresh Token", 10),
        TokenPrefix("glpat-", "GitLab Token", 20),
        TokenPrefix("hf_", "Hugging Face Token", 30),
        TokenPrefix("npm_", "npm Token", 36),
        TokenPrefix("ya29.", "Google OAuth Token", 20),
        TokenPrefix("shpat_", "Shopify Token", 20),
        TokenPrefix("dop_v1_", "DigitalOcean Token", 30),
        TokenPrefix("lin_api_", "Linear Key", 30),
        TokenPrefix("sk_test_", "Stripe Test Key", 16),
        TokenPrefix("SG.", "SendGrid Key", 40),
        TokenPrefix("ASIA", "AWS Session Token", 10),
        TokenPrefix("AKIA", "AWS Access Key", 10),
        TokenPrefix("sk-", "OpenAI API Key", 10)
    ]

    private static let awsPrefixes: Set<String> = ["AKIA", "ASIA"]

    /// An AWS access key id is its prefix and exactly sixteen capitals or digits.
    private static func hiddenCountPreview(prefix: String, label: String, hidden: Int) -> String {
        "\(prefix)•••• (\(label), " + String(localized: "\(hidden) characters hidden") + ")"
    }

    private static func awsKeyMatch(_ token: String) -> Result? {
        guard Patterns.awsKey.firstMatch(in: token, range: NSRange(token.startIndex..., in: token)) != nil else {
            return nil
        }
        let label = token.hasPrefix("ASIA") ? "AWS Session Token" : "AWS Access Key"
        return Result(
            category: .oauthToken,
            maskedPreview: hiddenCountPreview(prefix: String(token.prefix(4)), label: label, hidden: token.count - 4)
        )
    }

    private static func oauthTokenMatch(_ text: String) -> Result? {
        // A key is one token. Text that merely starts like one ("ASIAN GAMES 2026", "sk-learn is a library") is not.
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.contains(where: \.isWhitespace) else { return nil }
        if let aws = awsKeyMatch(token) { return aws }
        for entry in oauthPrefixes
            where !awsPrefixes.contains(entry.prefix) && text.hasPrefix(entry.prefix)
            && text.count >= entry.prefix.count + entry.minimumTail
        {
            let hiddenCount = text.count - entry.prefix.count
            let masked = hiddenCountPreview(prefix: entry.prefix, label: entry.label, hidden: hiddenCount)
            return Result(category: .oauthToken, maskedPreview: masked)
        }
        return nil
    }

    // MARK: - Private key block

    private static func privateKeyMatch(_ text: String) -> Result? {
        guard text.contains("-----BEGIN "), text.contains("PRIVATE KEY-----") else { return nil }
        return Result(category: .privateKey, maskedPreview: hiddenCountMask(text.count))
    }

    // MARK: - Password lines

    private static func passwordLineMatch(_ text: String) -> Result? {
        // Inline `password: foo` / `passwd=foo` style.
        if Patterns.passwordLine.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
            return Result(category: .password, maskedPreview: dotsOnlyMask)
        }
        // Bcrypt / argon2 hashes.
        if text.hasPrefix("$2a$") || text.hasPrefix("$2b$") || text.hasPrefix("$2y$") || text.hasPrefix("$argon2") {
            return Result(category: .password, maskedPreview: hiddenCountMask(text.count))
        }
        return nil
    }

    // MARK: - Secrets assigned or embedded inside larger text

    /// `API_KEY=...`, `client_secret: ...`, `GITHUB_TOKEN=...` on any line. The name has to end in a secret-like word
    /// and
    /// be followed straight away by `=` or `:`, so prose ("secret santa: December") is left alone.
    private static func secretAssignmentMatch(_ text: String) -> Result? {
        let range = NSRange(text.startIndex..., in: text)
        guard Patterns.secretAssignment.firstMatch(in: text, range: range) != nil else { return nil }
        return Result(category: .apiKey, maskedPreview: dotsOnlyMask)
    }

    /// Bearer tokens and vendor keys wherever they sit in the text, such as a pasted `curl` command.
    private static func embeddedTokenMatch(_ text: String) -> Result? {
        for regex in Patterns.embeddedTokens
            where regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        {
            return Result(category: .oauthToken, maskedPreview: dotsOnlyMask)
        }
        return nil
    }

    // MARK: - High-entropy API key

    private static func apiKeyMatch(_ text: String) -> Result? {
        // Single token, ≥32 chars, alphanumeric (+ `_-`), high Shannon entropy.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 32,
              !trimmed.contains(" "),
              !trimmed.contains("\n"),
              trimmed.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return nil }
        guard shannonEntropy(trimmed) >= 4.0 else { return nil }
        return Result(category: .apiKey, maskedPreview: hiddenCountMask(trimmed.count))
    }

    private static func shannonEntropy(_ s: String) -> Double {
        var counts: [Character: Int] = [:]
        for c in s {
            counts[c, default: 0] += 1
        }
        let length = Double(s.count)
        return counts.values.reduce(0.0) { acc, count in
            let p = Double(count) / length
            return acc - p * log2(p)
        }
    }

    /// The card wears the category as a badge, so the mask is dots and, where there is one, a count: a label in the
    /// text
    /// said the same thing twice.
    static let dotsOnlyMask = "••••"

    static func hiddenCountMask(_ count: Int) -> String {
        "•••• (" + String(localized: "\(count) characters hidden") + ")"
    }

    /// Formats a mask for a sensitive clip category at render time, for a clip that stored none.
    public static func localizedMask(for category: SensitivityCategory, count: Int? = nil) -> String {
        switch category {
        case .creditCard: "•••• •••• •••• ••••"
        case .ssn: "•••-••-••••"
        case .jwt, .apiKey:
            if let count, count > 0 { hiddenCountMask(count) } else { dotsOnlyMask }
        case .oauthToken, .privateKey, .password: dotsOnlyMask
        case .credential: String(localized: "Hidden credential")
        }
    }

    private static let oldCountMasks: [NSRegularExpression] = [
        #"^API key •••• \((\d+) characters? hidden\)$"#,
        #"^JWT \((\d+) characters?, 3 parts\)$"#,
        #"^Password hash \((\d+) characters?\)$"#
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    /// A mask stored by an older version, in the form the card shows now. A mask already in the new form, or one that
    /// carries information the badge does not (a vendor, the last four digits, the app that hid it), comes back as it
    /// was, so the rewrite is idempotent.
    public static func modernisedMask(_ mask: String) -> String {
        switch mask {
        case "Password line (hidden)", "Secret assignment (hidden)", "Access token (hidden)": return dotsOnlyMask
        case "•••-••-•••• (SSN)": return "•••-••-••••"
        case _ where mask.hasPrefix("🔒 ") && mask.hasSuffix("PRIVATE KEY"): return "•••• (private key hidden)"
        default: break
        }
        if mask.hasSuffix(" (card number in text)") {
            return String(mask.dropLast(" (card number in text)".count))
        }
        let range = NSRange(mask.startIndex..., in: mask)
        for regex in oldCountMasks {
            if let match = regex.firstMatch(in: mask, range: range),
               let digits = Range(match.range(at: 1), in: mask), let count = Int(mask[digits])
            {
                return hiddenCountMask(count)
            }
        }
        return mask
    }
}
