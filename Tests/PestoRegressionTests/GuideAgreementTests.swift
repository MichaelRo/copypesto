// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("Guide agreements and retired terms")
struct GuideAgreementTests {
    private static let validPanes: Set<String> = [
        "General",
        "Shortcuts",
        "Appearance",
        "Privacy",
        "Collections",
        "Snippets",
        "Data"
    ]

    private func guideFiles() throws -> [URL] {
        let docs = SourceTree.repositoryRoot.appendingPathComponent("docs/guide")
        let enumerator = try #require(FileManager.default.enumerator(at: docs, includingPropertiesForKeys: nil))
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "md" }
        #expect(files.count >= 8, "fewer guide files than expected: \(files.count)")
        return files
    }

    /// The documents outside the guide that tell a person or a contributor where something is: the README and the
    /// reference. `docs/copy-guide.md` is the glossary that names the retired words and `CHANGELOG.md` records what
    /// things used to be called, so neither is read.
    private func otherDocumentFiles() throws -> [URL] {
        let root = SourceTree.repositoryRoot
        let names = [
            "README.md", "ROADMAP.md", "CONTRIBUTING.md", "SECURITY.md", "SUPPORT.md", "docs/feature-reference.md",
            "docs/testing.md", "docs/development.md", "docs/design-language.md"
        ]
        let files = names.map { root.appendingPathComponent($0) }
        for file in files {
            #expect(FileManager.default.fileExists(atPath: file.path), "\(file.path) is gone")
        }
        return files
    }

    @Test("every Settings path in the guide names a real pane")
    func settingsPathsNameRealPanes() throws {
        let pattern = try NSRegularExpression(pattern: #"(?<!System\s)Settings\s*→\s*([A-Za-z]+)"#)
        for file in try guideFiles() + otherDocumentFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for match in pattern.matches(in: text, range: range) {
                guard let paneRange = Range(match.range(at: 1), in: text) else { continue }
                let pane = String(text[paneRange])
                #expect(
                    Self.validPanes.contains(pane),
                    "\(file.lastPathComponent) names invalid settings pane: '\(pane)'"
                )
            }
        }
    }

    @Test("no retired terms appear in the guide, the README or the reference")
    func retiredTermsDoNotAppearInGuide() throws {
        let retiredFile = SourceTree.repositoryRoot.appendingPathComponent("docs/retired-terms.txt")
        let retiredContent = try String(contentsOf: retiredFile, encoding: .utf8)
        let terms = retiredContent
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        #expect(!terms.isEmpty, "retired-terms.txt is empty")

        for file in try guideFiles() + otherDocumentFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            for term in terms {
                #expect(
                    !text.contains(term),
                    "\(file.lastPathComponent) contains retired term: '\(term)'"
                )
            }
        }
    }
}
