// SPDX-License-Identifier: MIT
import Foundation

/// Refines a string payload into a finer-grained `ClipboardType`. Runs after
/// `PasteboardTypeDetector` so we already know it's text. Detects hex colors, URLs, and code.
public enum ContentClassifier {
    public struct Result: Sendable, Equatable {
        public let type: ClipboardType
        public let detectedLanguage: String?
        public let extractedURL: URL?

        public init(type: ClipboardType, detectedLanguage: String? = nil, extractedURL: URL? = nil) {
            self.type = type
            self.detectedLanguage = detectedLanguage
            self.extractedURL = extractedURL
        }
    }

    /// Matches all common CSS color formats:
    /// - `#RGB` / `#RRGGBB` / `#RRGGBBAA` (hash required for 3-char shorthand)
    /// - `RRGGBB` / `RRGGBBAA` (hash optional for 6/8-char forms, but a run of digits alone is a number)
    /// The functional forms (`rgb()`, `rgba()`, `hsl()`, `hsla()`) are read by `ColorLiteralParser.isFunctionalColor`.
    private static let colorPatternRegex = try? NSRegularExpression(
        pattern: #"^(#(?:[0-9A-Fa-f]{3,4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})|[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?)$"#,
        options: [.caseInsensitive]
    )

    /// Standalone URL — leading/trailing whitespace tolerated.
    private static let urlRegex = try? NSRegularExpression(
        pattern: #"^\s*(https?|file)://\S+\s*$"#,
        options: [.caseInsensitive]
    )

    /// Strong code anchors — one match alone classifies the text as code, and the
    /// associated language is returned without further keyword counting. These
    /// patterns are deliberately conservative so prose like "let's also fix bugs"
    /// or "function as a noun" never trips them.
    private static let strongAnchorPatterns: [(String, String)] = [
        // Order matters — more specific anchors first so `func main()` after
        // `package main` is correctly attributed to Go, not Swift.
        ("shell", #"^#!\s*/"#), // shebang
        ("go", #"^package\s+\w+\s*$"#), // Go package decl
        ("go", #"\bfunc\s+\(\w+\s+\*?\w+\)\s+\w+\("#), // receiver func
        ("html", #"<!DOCTYPE\s+html"#),
        ("html", #"<(html|body|head|script|style)\b[^>]*>"#),
        ("python", #"\bdef\s+\w+\s*\("#), // def foo(
        ("python", #"\bif\s+__name__\s*==\s*['\"]__main__"#),
        ("rust", #"\bpub\s+(fn|struct|enum)\b"#),
        ("rust", #"\bfn\s+\w+\s*(<[^>]+>)?\s*\("#), // fn foo(
        ("javascript", #"\bfunction\s+\w+\s*\("#), // function foo(
        ("javascript", #"\bconst\s+\w+\s*=\s*(\([^)]*\)\s*=>|async\s)"#),
        ("javascript", #"\b(require|module\.exports)\s*\("#),
        ("swift", #"\b@MainActor\b"#), // attribute
        ("swift", #"\bimport\s+(Foundation|SwiftUI|UIKit|AppKit|Combine|SwiftData)\b"#),
        ("swift", #"\bfunc\s+\w+\s*(<[^>]+>)?\s*\("#), // func foo(
        ("ruby", #"\bclass\s+[A-Z]\w*(\s*<\s*[A-Z]\w*)?\s*$"#),
        ("sql", #"\b(SELECT\s+[\w*,\s]{1,200}?\s+FROM|INSERT\s+INTO\s+\w+|CREATE\s+TABLE)\b"#),
        ("markdown-fence", "```[a-zA-Z0-9_+-]*\\n") // ```lang\n
    ]

    private static let compiledStrongAnchors: [(String, NSRegularExpression)] = strongAnchorPatterns
        .compactMap { language, pattern in
            regex(pattern).map { (language, $0) }
        }

    /// Weak language keywords — need multiple distinct hits plus structural
    /// punctuation to classify as code. Tuned to avoid prose false positives.
    private static let weakKeywordPatterns: [(String, String)] = [
        ("swift", #"\b(guard|struct|protocol|extension)\b"#),
        ("python", #"\b(lambda|elif|yield|raise)\b"#),
        ("javascript", #"\b(=>|await|async\s+function|export\s+(default|const|function))"#),
        ("rust", #"\b(impl\s+\w|trait\s+\w|match\s+\w+\s*\{|Result<)"#),
        ("go", #"\b(interface\s*\{|chan\s+\w|defer\s+\w)\b"#),
        ("ruby", #"\b(attr_accessor|attr_reader|puts\s+["'])"#),
        ("shell", #"^\s*\$\s+\w"#),
        ("html", #"<\/[a-z]+>"#),
        ("sql", #"\b(WHERE\s+\w+\s*=|GROUP\s+BY|ORDER\s+BY)\b"#)
    ]

    private static let compiledWeakKeywords: [(String, NSRegularExpression)] = weakKeywordPatterns
        .compactMap { language, pattern in
            regex(pattern).map { (language, $0) }
        }

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }

    /// The code heuristics read this much of a copy: the first 50,000 characters say what kind of text it is, and the
    /// patterns are run over it several times each, so a 10 MB copy must not cost 10 MB of regex work.
    static let maxAnalysedCharacters = 50_000

    /// Structural evidence — paired with weak keywords to confirm "this is code,
    /// not prose that happens to use a programming word."
    private static let structuralCharRegex = try? NSRegularExpression(
        pattern: #"(?:\{[\s\S]{0,4000}?\}|;\s*$|=>|::|\)\s*\{)"#,
        options: [.anchorsMatchLines]
    )

    private static func isBareNumber(_ text: String) -> Bool {
        text.allSatisfy(\.isASCII) && text.allSatisfy(\.isNumber)
    }

    /// `#178`, `#404` or `#1234`: differing digits after a hash are an issue number or a status code far more often
    /// than
    /// a colour, and `#cafe` is a hashtag (`HexColorParser.isAmbiguousShorthand`). `#000`, `#999`, `#ffff`, `#f008` and
    /// three characters with a letter stay colours.
    private static func isReferenceNumber(_ text: String) -> Bool {
        text.hasPrefix("#") && HexColorParser.isAmbiguousShorthand(text.dropFirst())
    }

    /// `decade`, `facade`, `deadbeef`: six or eight letters that all happen to be hex digits are a word. A colour's
    /// preview is the one preview stored unencrypted (ADR 0002), so a word must not be taken for one.
    private static func isBareLettersWord(_ text: String) -> Bool {
        !text.hasPrefix("#") && text.allSatisfy(\.isLetter)
    }

    /// Classify a plain-text payload. Returns the best refinement, defaulting to `.text`.
    public static func classify(text: String) -> Result {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Result(type: .text) }

        let range = NSRange(trimmed.startIndex..., in: trimmed)

        // Color literals: hex, rgb(), rgba(), hsl(), hsla()
        if let regex = colorPatternRegex,
           regex.numberOfMatches(in: trimmed, range: range) > 0,
           !isBareNumber(trimmed), !isReferenceNumber(trimmed), !isBareLettersWord(trimmed)
        {
            return Result(type: .color)
        }
        if ColorLiteralParser.isFunctionalColor(trimmed) { return Result(type: .color) }

        // URL
        if let regex = urlRegex,
           regex.numberOfMatches(in: trimmed, range: range) > 0,
           let url = URL(string: trimmed)
        {
            return Result(type: .url, extractedURL: url)
        }

        if SVGThumbnail.isSVGDocument(trimmed) {
            return Result(type: .code, detectedLanguage: ClipboardType.svgLanguage)
        }

        if JSONText.isJSONDocument(trimmed) {
            return Result(type: .code, detectedLanguage: JSONText.language)
        }

        // Code (heuristic): at least two distinct language groups OR an unambiguous shebang.
        if let language = detectCodeLanguage(in: String(text.prefix(maxAnalysedCharacters))) {
            return Result(type: .code, detectedLanguage: language)
        }

        if MarkdownDetector.isMarkdown(String(text.prefix(maxAnalysedCharacters))) {
            return Result(type: .text, detectedLanguage: MarkdownDetector.language)
        }

        return Result(type: .text)
    }

    private static func detectCodeLanguage(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)

        // Tier 1: a single strong anchor is enough. Markdown fences declare their
        // own language; fall through to weak-keyword matching to pick a label.
        for (language, regex) in compiledStrongAnchors where regex.numberOfMatches(in: text, range: range) > 0 {
            if language == "markdown-fence" {
                // Fence opens; pick the dominant weak language inside or default to "text".
                return dominantWeakLanguage(in: text, range: range) ?? "text"
            }
            return language
        }

        // Tier 2: ≥3 distinct weak languages AND structural punctuation. Prevents
        // prose like "let's also fix bugs and functions" from triggering code.
        let hits = weakLanguageHits(in: text, range: range)
        guard hits.count >= 3 else { return nil }
        guard let regex = structuralCharRegex,
              regex.numberOfMatches(in: text, range: range) > 0 else { return nil }
        return hits.max { $0.value < $1.value }?.key
    }

    private static func weakLanguageHits(in text: String, range: NSRange) -> [String: Int] {
        var matches: [String: Int] = [:]
        for (language, regex) in compiledWeakKeywords {
            let count = regex.numberOfMatches(in: text, range: range)
            if count > 0 {
                matches[language, default: 0] += count
            }
        }
        return matches
    }

    private static func dominantWeakLanguage(in text: String, range: NSRange) -> String? {
        weakLanguageHits(in: text, range: range).max { $0.value < $1.value }?.key
    }
}
