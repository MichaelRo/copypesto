// SPDX-License-Identifier: MIT
import Foundation

/// Plain text that is written in Markdown, so `@markdown` finds it. Two different kinds of markup are needed: one
/// stray `#` or `*` is not a document.
enum MarkdownDetector {
    static let language = ClipboardType.markdownLanguage

    private static let signals: [NSRegularExpression] = [
        #"(?m)^#{1,6}\s+\S"#, // heading
        #"(?m)^ {0,3}([-*+]|\d{1,3}\.) +\S[^\n]{0,300}\n {0,3}([-*+]|\d{1,3}\.) +\S"#, // two list items in a row
        #"\[[^\]\n]{1,200}\]\((https?://|/|#|\.)[^)\s]{0,500}\)"#, // link
        #"\*\*[^*\n]{1,200}\*\*|__[^_\n]{1,200}__"#, // bold
        #"(?m)^>\s+\S"#, // quote
        #"(?m)^\|[^\n]{1,300}\|[ \t]*\n\|\s*:?-{2,}"#, // table
        #"(?m)^```"#, // fence
        #"`[^`\n]{1,200}`"# // inline code
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    static func isMarkdown(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        var found = 0
        for signal in signals where signal.firstMatch(in: text, range: range) != nil {
            found += 1
            if found == 2 { return true }
        }
        return false
    }
}
