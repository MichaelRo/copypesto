// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// The analytics-SDK list differed in four places and `make verify` was said to take 4, 25 and 40 minutes.
/// A claim that lives in more than one file is pinned here.
@Suite("Docs agree with the tooling")
struct DocsAgreeWithToolingTests {
    private func text(_ relative: String) throws -> String {
        try String(contentsOf: SourceTree.repositoryRoot.appendingPathComponent(relative), encoding: .utf8)
    }

    private func shellList(in relative: String) throws -> Set<String> {
        let source = try text(relative)
        let expression = try NSRegularExpression(pattern: #"forbidden=\(([^)]*)\)"#)
        let range = NSRange(source.startIndex..., in: source)
        let match = try #require(expression.firstMatch(in: source, range: range), "no forbidden=(…) in \(relative)")
        let list = try #require(Range(match.range(at: 1), in: source))
        return Set(source[list].split(separator: " ").map(String.init))
    }

    @Test("CI and the pre-push hook grep for the same analytics SDKs, and AGENTS.md names every one")
    func analyticsListsAgree() throws {
        let ci = try shellList(in: ".github/workflows/ci.yml")
        let hook = try shellList(in: ".githooks/pre-push")
        #expect(ci == hook, "ci.yml and pre-push disagree: \(ci.symmetricDifference(hook).sorted())")
        let claude = try text("AGENTS.md")
        for name in ci {
            #expect(claude.contains("`\(name)`"), "AGENTS.md does not name \(name)")
        }
    }

    @Test("the full gate is described with one duration everywhere")
    func gateDurationAgrees() throws {
        for file in ["AGENTS.md", "Makefile", "docs/testing.md"] {
            #expect(try text(file).contains("about 40 minutes"), "\(file) gives another duration for the full gate")
        }
    }
}
