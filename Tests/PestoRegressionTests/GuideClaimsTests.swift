// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The guide states what the code does")
struct GuideClaimsTests {
    private func guide(_ name: String) throws -> String {
        try String(contentsOf: SourceTree.repositoryRoot.appendingPathComponent(name), encoding: .utf8)
    }

    @Test("Paste As lists the transforms there are and counts them from the enum (V-A7)")
    func transformsAreTrue() throws {
        let text = try guide("docs/guide/using-pesto.md")
        #expect(
            text.contains("\(TextTransform.allCases.count) transforms"),
            "the count is not \(TextTransform.allCases.count)"
        )
        #expect(!text.contains("snake_case") && !text.contains("kebab-case"), "Pesto has no such conversion")
        for name in ["camelCase", "PascalCase", "Slug-Case"] {
            #expect(text.contains(name), "\(name) is a transform the guide does not list")
        }
    }

    @Test("the feature reference does not claim snippet files Pesto cannot read (V-A7)")
    func snippetImportClaimIsTrue() throws {
        let text = try guide("docs/feature-reference.md")
        #expect(!text.contains("snippets files from Raycast, TextExpander or Alfred"))
    }

    @Test("⌘⌥V is only ever named as history: paste the previous clip starts unset (ADR 0012)")
    func pastePreviousIsNotADefault() throws {
        #expect(GlobalShortcut.pastePrevious.defaultBinding == nil, "the default came back; update the guides")
        // ⌃⌥⌘V (plain text) contains ⌥⌘V, so a control key in front rules the match out.
        let namesIt = try NSRegularExpression(pattern: "(?<!⌃)(⌘⌥V|⌥⌘V)")
        let history = ["was ", "before", "no longer", "keep it", "keeps it"]
        let root = SourceTree.repositoryRoot
        var files = try SourceTree.files(in: "docs/guide", extensions: ["md"], minimum: 5, under: root)
        files += try SourceTree.files(in: "Sources/Features", minimum: 100, under: root)
        files += ["README.md", "docs/feature-reference.md", "CONTRIBUTING.md"].map { root.appendingPathComponent($0) }
        var offenders: [String] = []
        for file in files {
            for (number, line) in try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
                .enumerated()
                where namesIt.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
                && !history.contains(where: line.contains)
            {
                offenders.append("\(SourceTree.relativePath(file)):\(number + 1)")
            }
        }

        #expect(offenders.isEmpty, "name ⌘⌥V only as what it used to be: \(offenders.joined(separator: ", "))")
    }

    @Test("the numbers the docs give for Undo and the History Lock window are the code's")
    func limitsInProseAreTheCodes() throws {
        let megabyte = 1024 * 1024
        let reference = try guide("docs/feature-reference.md")
        #expect(reference.contains("The last \(UndoPolicy.maxEntries) actions"), "the Undo entry count changed")
        #expect(reference.contains("at most \(UndoPolicy.maxHeldBytes / megabyte) MB"), "the Undo size limit changed")
        #expect(
            reference.contains("clips over \(UndoPolicy.maxClipBytes / megabyte) MB"),
            "the Undo clip limit changed"
        )
        let privacy = try guide("docs/guide/privacy-and-security.md")
        #expect(privacy.contains("clips over \(UndoPolicy.maxClipBytes / megabyte) MB are never kept"))
        let settings = try guide("docs/guide/settings.md")
        #expect(AuthenticationGrace.choices == [1, 5, 15, 60], "the grace choices changed; update the guides")
        #expect(settings.contains("(1, 5, 15 minutes or 1 hour)"))
        #expect(privacy.contains("1, 5, 15 or 60 minutes"))
    }
}
