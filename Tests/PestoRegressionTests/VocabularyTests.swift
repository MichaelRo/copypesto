// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// `docs/copy-guide.md` fixes the words: a saved copy is a "clip", a named group is a "collection", and "item",
/// "entry" and "pinboard" are not used for either. Log lines are not read by anyone in the UI and are left alone.
@Suite("Vocabulary in the user interface")
struct VocabularyTests {
    private static let banned = try? NSRegularExpression(
        pattern: #"pinboard|clipboard items?|\bitems?\b|\bentr(?:y|ies)\b|\boverlay\b|"#
            + #"\btap(?:s|ping|ped)?\b|\bno cloud\b"#,
        options: .caseInsensitive
    )
    private static let literal = try? NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*""#)
    private static let interpolation = try? NSRegularExpression(pattern: #"\\\((?:[^()]|\([^()]*\))*\)"#)

    /// macOS's own name for a System Settings pane.
    private static let systemTerms = ["Login Items"]

    /// Paste's own word for its groups, spoken about Paste in the import sheet.
    private static let allowedFiles: Set<String> = ["PasteImportSheet.swift"]

    /// British spellings; the UI is American English like macOS (`docs/copy-guide.md`, Spelling). Search keywords in
    /// `SettingsIndex` may list both and live in Core, which is not scanned.
    private static let british = try? NSRegularExpression(
        pattern: #"colour|sanitis|greyed|\bgrey\b|favourite|organis|summaris|behaviour|cancelled|centre\b|licence|"#
            + #"recognis|analys(?:e|ed|ing)\b|catalogue"#,
        options: .caseInsensitive
    )

    @Test("no sentence in the UI says item, entry or pinboard where the guide says clip or collection")
    func noOffVocabularyWords() throws {
        let offenders = try Self.spokenLiterals().filter { literal in
            var spoken = literal.spoken
            for term in Self.systemTerms {
                spoken = spoken.replacingOccurrences(of: term, with: "")
            }
            return Self.banned?.firstMatch(in: spoken, range: NSRange(spoken.startIndex..., in: spoken)) != nil
        }.map(\.location)

        #expect(offenders.isEmpty, "off-vocabulary words: \(offenders.joined(separator: "; "))")
    }

    @Test("Control is written with its own glyph, never as a caret before a digit")
    func noCaretControlKey() throws {
        let caret = try NSRegularExpression(pattern: #"(?<![\w`])\^[1-9]\b"#)
        let offenders = try Self.spokenLiterals().filter { literal in
            caret
                .firstMatch(in: literal.spoken, range: NSRange(literal.spoken.startIndex..., in: literal.spoken)) != nil
        }.map(\.location)

        #expect(offenders.isEmpty, "write \u{2303}1, not ^1: \(offenders.joined(separator: "; "))")
    }

    @Test("UI text uses American spelling (color, sanitize, grayed, canceled)")
    func noBritishSpellings() throws {
        let offenders = try Self.spokenLiterals().filter { literal in
            Self.british?.firstMatch(
                in: literal.spoken,
                range: NSRange(literal.spoken.startIndex..., in: literal.spoken)
            )
                != nil
        }.map(\.location)

        #expect(offenders.isEmpty, "British spellings: \(offenders.joined(separator: "; "))")
    }

    /// Every string literal in `Features`, `App` and `CLI` that reads as a phrase (has a space), with interpolations
    /// removed; each line of a multi-line literal counts as one. Comments, log lines and privacy annotations are
    /// skipped.
    private static func spokenLiterals() throws -> [(location: String, spoken: String)] {
        var literals: [(location: String, spoken: String)] = []
        for (folder, minimum) in [("Features", 60), ("App", 30), ("CLI", 1)] {
            let files = try SourceTree.swiftFiles(in: folder, minimum: minimum)
            for file in files where !Self.allowedFiles.contains(file.lastPathComponent) {
                let text = try String(contentsOf: file, encoding: .utf8)
                var insideMultiLine = false
                for (number, line) in text.components(separatedBy: "\n").enumerated() {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasSuffix(#"""""#) {
                        insideMultiLine.toggle()
                        continue
                    }
                    if trimmed.hasPrefix("//") || line.contains("privacy:") || line.lowercased()
                        .contains("logger") { continue }
                    let range = NSRange(line.startIndex..., in: line)
                    let sentences = insideMultiLine ? [trimmed] : (Self.literal?.matches(in: line, range: range) ?? [])
                        .compactMap { Range($0.range, in: line).map { String(line[$0]) } }
                    for sentence in sentences {
                        let spoken = Self.interpolation?.stringByReplacingMatches(
                            in: sentence, range: NSRange(sentence.startIndex..., in: sentence), withTemplate: ""
                        ) ?? sentence
                        guard spoken.contains(" "), !spoken.contains("outcome=") else { continue }
                        literals.append(("\(file.lastPathComponent):\(number + 1) \(sentence.prefix(70))", spoken))
                    }
                }
            }
        }
        return literals
    }

    static let handMadePluralPattern =
        #"\(s\)|[=!]= 1 \? "|> 1 \? "|\? "s?" : "s?"|case 1:\s*"1 "#

    @Test("the plural scan recognises the hand-made forms it exists to catch")
    func handMadePluralPatternMatchesKnownForms() throws {
        let pattern = try NSRegularExpression(pattern: Self.handMadePluralPattern)
        func matches(_ line: String) -> Bool {
            pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
        }
        #expect(matches(#"Text("\(n) clip(s)")"#))
        #expect(matches(#"let label = count == 1 ? "1 tag" : "\(count) tags""#))
        #expect(matches(#"let plural = names.count > 1 ? "s" : """#))
        #expect(matches(#""\(count) \(unit)\(count == 1 ? "" : "s") ago""#))
        #expect(matches(#"case 1: "1 minute""#))
        #expect(!matches(#"Text("\(count) clips")"#))
        #expect(!matches(#"let found = index == 1"#))
    }

    @Test("no sentence builds a plural by hand: use a String Catalog plural, not \"(s)\" or a count ternary")
    func noHandMadePlurals() throws {
        let handMade = try NSRegularExpression(pattern: Self.handMadePluralPattern)
        var offenders: [String] = []
        for (folder, minimum) in [("Features", 60), ("App", 30), ("CLI", 1)] {
            let files = try SourceTree.swiftFiles(in: folder, minimum: minimum)
            for file in files {
                let text = try String(contentsOf: file, encoding: .utf8)
                for (number, line) in text.components(separatedBy: "\n").enumerated() {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("//") { continue }
                    if handMade.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                        offenders.append("\(file.lastPathComponent):\(number + 1)")
                    }
                }
            }
        }

        #expect(offenders.isEmpty, "hand-made plurals: \(offenders.joined(separator: ", "))")
    }
}
