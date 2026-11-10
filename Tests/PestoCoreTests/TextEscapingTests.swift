// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("TextTransform escaping")
struct TextEscapingTests {
    private static let samples = [
        "plain",
        "",
        "  leading and trailing  ",
        "say \"hi\"",
        "back\\slash",
        "line one\nline two\r\ncarriage\ttabbed",
        "emoji 😀 and ü",
        "<a href=\"x\">&</a>",
        "a'\u{0301}; rm -rf ~",
        ".\u{0301}*\u{0301}<\u{0301}&\u{0301}\"\u{0301}"
    ]

    @Test("each escape has an unescape that returns the original", arguments: [
        (TextTransform.jsonEscape, TextTransform.jsonUnescape),
        (.backslashEscape, .backslashUnescape),
        (.unicodeEscape, .unicodeUnescape),
        (.htmlEncode, .htmlDecode)
    ])
    func whenEscapedThenUnescaped_thenOriginal(escape: TextTransform, unescape: TextTransform) {
        for sample in Self.samples {
            #expect(unescape.apply(to: escape.apply(to: sample)) == sample, "\(escape) -> \(sample)")
        }
    }

    @Test("JSON escape produces a string body, with no surrounding quotes")
    func whenJSONEscape_thenBodyOnly() {
        #expect(TextTransform.jsonEscape.apply(to: "a \"b\"\n/") == #"a \"b\"\n/"#)
    }

    @Test("JSON unescape takes a quoted string and preserves leading and trailing whitespace when unquoted")
    func whenJSONUnescape_thenQuotedAndWhitespacePreserved() {
        #expect(TextTransform.jsonUnescape.apply(to: #""a \"b\"\u00fc""#) == "a \"b\"ü")
        #expect(TextTransform.jsonUnescape.apply(to: "  hello  ") == "  hello  ")
        #expect(TextTransform.jsonUnescape.apply(to: "  \\ta\\n  ") == "  \ta\n  ")
    }

    @Test("input that is not a valid escaped string is returned unchanged")
    func whenInvalidInput_thenUnchanged() {
        #expect(TextTransform.jsonUnescape.apply(to: #"bad \u12"#) == #"bad \u12"#)
        #expect(TextTransform.jsonUnescape.apply(to: "line1\nline2") == "line1\nline2")
        #expect(TextTransform.jsonUnescape.apply(to: #""abc\""#) == #""abc\""#)
        #expect(TextTransform.unicodeUnescape.apply(to: #"\u{ZZ}"#) == #"\u{ZZ}"#)
    }

    @Test("HTML encode escapes the five characters, decode reads numeric and common named entities")
    func whenHTML_thenEntities() {
        #expect(TextTransform.htmlEncode.apply(to: "<a b=\"c\">&'") == "&lt;a b=&quot;c&quot;&gt;&amp;&#39;")
        #expect(TextTransform.htmlDecode.apply(to: "&#65;&#x42;&amp;lt;") == "AB&lt;")
        #expect(TextTransform.htmlDecode.apply(to: "&copy; 2026 &mdash; &hellip; &euro;") == "© 2026 — … €")
    }

    @Test("unicode escape uses UTF-16 code units and unescape reads both surrogate pairs and Swift braces")
    func whenUnicodeEscape_thenInteroperable() {
        #expect(TextTransform.unicodeEscape.apply(to: "aü😀") == #"a\u00fc\ud83d\ude00"#)
        #expect(TextTransform.unicodeUnescape.apply(to: #"a\u00fc\ud83d\ude00"#) == "aü😀")
        #expect(TextTransform.unicodeUnescape.apply(to: #"a\u00fc\u{1f600}"#) == "aü😀")
    }

    @Test("unicode unescape honors backslash parity so an escaped backslash stays literal")
    func whenEscapedBackslashBeforeU_thenParityRespected() {
        #expect(TextTransform.unicodeUnescape.apply(to: #"\\u00fc"#) == #"\\u00fc"#)
        #expect(TextTransform.unicodeUnescape.apply(to: #"\\\u00fc"#) == #"\\ü"#)
    }

    @Test("combining marks right after special characters still escape the special character")
    func whenCombiningMarkAfterSpecialChar_thenStillEscaped() {
        #expect(TextTransform.shellQuote.apply(to: "'\u{0301}") == "''\\''\u{0301}'")
        #expect(TextTransform.regexEscape.apply(to: ".\u{0301}*") == "\\.\u{0301}\\*")
        #expect(TextTransform.htmlEncode.apply(to: "<\u{0301}") == "&lt;\u{0301}")
        #expect(TextTransform.backslashEscape.apply(to: "\"\u{0301}") == "\\\"\u{0301}")
    }

    @Test("regex escape escapes every metacharacter")
    func whenRegexEscape_thenMetacharactersEscaped() {
        #expect(TextTransform.regexEscape.apply(to: "a.b*c(d)[e]{f}|g^h$i+j?k\\") ==
            #"a\.b\*c\(d\)\[e\]\{f\}\|g\^h\$i\+j\?k\\"#)
    }

    @Test("shell quote wraps in single quotes and escapes embedded ones")
    func whenShellQuote_thenSingleQuoted() {
        #expect(TextTransform.shellQuote.apply(to: "it's $HOME") == #"'it'\''s $HOME'"#)
    }

    @Test("text clips keep plain text out of Case and keep case transforms at the top level")
    func whenGrouping_thenPlainTextSeparateAndSubmenusOrdered() {
        let text = TextTransform.grouped(TextTransform.available(for: .text))
        #expect(text.map(\.group) == [.plainText, .caseAndNaming, .lines, .encoding, .escaping, .hashing])
        #expect(TextTransform.stripFormatting.group == .plainText)
        #expect(!TextTransform.Group.caseAndNaming.isSubmenu)
        #expect(TextTransform.Group.lines.isSubmenu)
        #expect(TextTransform.Group.escaping.isSubmenu)
        #expect(TextTransform.available(for: .color).count <= 8)
        #expect(TextTransform.available(for: .url).count <= 8)
    }

    @Test("URL clips offer escaping that makes sense for an address")
    func whenURL_thenEncodeDecodeOffered() {
        let url = TextTransform.available(for: .url)
        #expect(url.contains(.urlEncode) && url.contains(.urlDecode))
    }

    @Test("control characters survive a JSON round trip")
    func whenControlCharacters_thenJSONRoundTrips() {
        let text = "a\u{01}b\u{08}c\u{0C}d\u{1F}"
        let escaped = TextTransform.jsonEscape.apply(to: text)
        #expect(escaped == #"a\u0001b\bc\fd\u001f"#)
        #expect(TextTransform.jsonUnescape.apply(to: escaped) == text)
    }

    @Test("a lone trailing backslash is not an escape, so the text is left alone")
    func whenTrailingBackslash_thenBackslashUnescapeUnchanged() {
        #expect(TextTransform.backslashUnescape.apply(to: "path\\") == "path\\")
    }

    @Test("an unknown backslash sequence is kept as typed")
    func whenUnknownSequence_thenKept() {
        #expect(TextTransform.backslashUnescape.apply(to: #"a\qb\d"#) == #"a\qb\d"#)
    }

    @Test("a lone surrogate or a value past U+10FFFF is not a character, so unicode unescape leaves the text")
    func whenInvalidScalar_thenUnicodeUnescapeUnchanged() {
        #expect(TextTransform.unicodeUnescape.apply(to: #"\ud83d"#) == #"\ud83d"#)
        #expect(TextTransform.unicodeUnescape.apply(to: #"\ud83d\u0041"#) == #"\ud83d\u0041"#)
        #expect(TextTransform.unicodeUnescape.apply(to: #"\u{110000}"#) == #"\u{110000}"#)
    }

    @Test("HTML decode leaves an unknown entity, zero, out-of-range, and a bare ampersand as they are")
    func whenUnknownEntity_thenKept() {
        #expect(TextTransform.htmlDecode.apply(to: "&bogus; & &amp") == "&bogus; & &amp")
        #expect(TextTransform.htmlDecode.apply(to: "&#0; &#xD800; &#x110000; &#999999999999;") ==
            "&#0; &#xD800; &#x110000; &#999999999999;")
    }

    @Test("empty input is stable for every escaping transform")
    func whenEmpty_thenStable() {
        #expect(TextTransform.shellQuote.apply(to: "") == "''")
        for transform in TextTransform.allCases where transform.group == .escaping && transform != .shellQuote {
            #expect(transform.apply(to: "").isEmpty, "\(transform)")
        }
    }

    @Test("every escaping transform keeps multi-line text on its lines")
    func whenMultiline_thenEscapesNeverLoseText() {
        let text = "first \"line\"\nsecond 'line'\n\tthird"
        #expect(TextTransform.shellQuote.apply(to: text).hasPrefix("'first"))
        #expect(TextTransform.backslashUnescape.apply(to: TextTransform.backslashEscape.apply(to: text)) == text)
    }

    @Test("text and code clips offer the escaping group; colors and links do not")
    func whenAvailability_thenEscapingForTextAndCode() {
        for type in [ClipboardType.text, .code] {
            let groups = TextTransform.grouped(TextTransform.available(for: type)).map(\.group)
            #expect(groups.contains(.escaping), "\(type)")
        }
        #expect(!TextTransform.available(for: .color).contains { $0.group == .escaping })
        #expect(!TextTransform.available(for: .url).contains { $0.group == .escaping })
    }

    @Test("every transform belongs to exactly one group and has a symbol")
    func whenAllCases_thenGroupedAndSymbolled() {
        let grouped = TextTransform.grouped(TextTransform.allCases).flatMap(\.transforms)
        #expect(grouped.count == TextTransform.allCases.count)
        #expect(TextTransform.allCases.allSatisfy { !$0.symbolName.isEmpty })
        #expect(Set(TextTransform.allCases.map(\.rawValue)).count == TextTransform.allCases.count)
    }
}
