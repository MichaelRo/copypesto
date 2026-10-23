// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// A sentence that prints a count says "1 clip", never "1 clips", so it needs a plural entry in the String Catalog.
/// `Core` has no catalog of its own: its sentences go through `String(localized:)`, which reads the app's.
@Suite("Count sentences are localised")
struct CountSentenceTests {
    private static let countNouns =
        "chars|characters|clips|days|collections|deletions|tags|hours|minutes|seconds"
    private static let countLiteral = try? NSRegularExpression(
        pattern: #""(?:[^"\\]|\\.)*\\\((?:[^()]|\([^()]*\))*\) (?:"# + countNouns + #")\b(?:[^"\\]|\\.)*""#
    )
    private static let interpolation = try? NSRegularExpression(pattern: #"\\\((?:[^()]|\([^()]*\))*\)"#)
    private static let placeholder = try? NSRegularExpression(pattern: #"%(?:\d+\$)?(?:lld|d|@)"#)

    private static func catalogKeys() throws -> Set<String> {
        let url = SourceTree.sources.appendingPathComponent("Resources/Localizable.xcstrings")
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let strings = try #require(catalog?["strings"] as? [String: Any])
        return Set(strings.keys.map { replace(placeholder, in: $0) })
    }

    private static func replace(_ expression: NSRegularExpression?, in text: String) -> String {
        guard let expression else { return text }
        return expression.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "%"
        )
    }

    @Test("the scan finds a count sentence and ignores one without a count")
    func scanRecognisesCountSentences() {
        func matches(_ line: String) -> Bool {
            Self.countLiteral?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
        }
        #expect(matches(#"Text("\(count) clips")"#))
        #expect(matches(#"String(localized: "JWT (\(text.count) chars, 3 parts)")"#))
        #expect(!matches(#"Text("Clips")"#))
        #expect(!matches(#"Text("\(name) was copied")"#))
    }

    @Test(
        "a sentence that prints a count has a catalog plural, and Core reaches it through String(localized:)"
    )
    func countSentencesHaveCatalogEntries() throws {
        let keys = try Self.catalogKeys()
        var offenders: [String] = []
        for (folder, minimum) in SourceTree.minimumFileCounts.sorted(by: { $0.key < $1.key }) where folder != "CLI" {
            for file in try SourceTree.swiftFiles(in: folder, minimum: minimum) {
                let text = try String(contentsOf: file, encoding: .utf8)
                for (number, line) in text.components(separatedBy: "\n").enumerated() {
                    if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") || line.contains("privacy:") {
                        continue
                    }
                    let range = NSRange(line.startIndex..., in: line)
                    for match in Self.countLiteral?.matches(in: line, range: range) ?? [] {
                        guard let literalRange = Range(match.range, in: line) else { continue }
                        let literal = String(line[literalRange].dropFirst().dropLast())
                        let key = Self.replace(Self.interpolation, in: literal)
                        let place = "\(file.lastPathComponent):\(number + 1)"
                        if !keys.contains(key) {
                            offenders.append("\(place) has no catalog entry for \"\(literal)\"")
                        } else if folder == "Core", !line.contains("String(localized:") {
                            offenders.append("\(place) builds \"\(literal)\" in Core outside String(localized:)")
                        }
                    }
                }
            }
        }
        #expect(offenders.isEmpty, "\(offenders.joined(separator: "; "))")
    }
}
