// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// Decisions were folded twice (fifty-odd into thirty, then thirty-nine into thirteen), and comments and notes kept
/// citing the old numbers. A citation of a decision that does not exist fails here, and so does a record that is not
/// in the shape the README describes.
@Suite("Decision references")
struct DecisionReferenceTests {
    private static let folders = ["Sources", "Tests", "docs", "scripts", "design", ".claude"]
    private static let rootFiles = [
        "AGENTS.md", "README.md", "CONTRIBUTING.md", "SECURITY.md", "SUPPORT.md", "TRADEMARKS.md",
        "decisions/README.md"
    ]
    private static let extensions: Set<String> = ["swift", "md", "txt", "yml", "sh", "py"]
    /// Reviews quote the stale numbers they found as evidence.
    private static let reviewReportSuffix = "-review-2026-10-14.md"

    private func existingNumbers() throws -> Set<String> {
        let directory = SourceTree.repositoryRoot.appendingPathComponent("decisions")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let numbers = names.compactMap { name in
            name.range(of: #"^\d{4}(?=-)"#, options: .regularExpression).map { String(name[$0]) }
        }
        return Set(numbers)
    }

    private func citations(in text: String) throws -> [String] {
        let run = try NSRegularExpression(pattern: #"ADRs?\s*#?(\d{4}(?:\s*(?:,|/|and|–|to)\s*\d{4})*)"#)
        let path = try NSRegularExpression(pattern: #"decisions/(\d{4})-"#)
        let whole = NSRange(text.startIndex..., in: text)
        var found: [String] = []
        for match in run.matches(in: text, range: whole) {
            guard let range = Range(match.range(at: 1), in: text) else { continue }
            found += text[range].split(whereSeparator: { !$0.isNumber }).map(String.init)
        }
        for match in path.matches(in: text, range: whole) {
            if let range = Range(match.range(at: 1), in: text) { found.append(String(text[range])) }
        }
        return found
    }

    private func filesToScan() throws -> [URL] {
        let root = SourceTree.repositoryRoot
        var files: [URL] = []
        for folder in Self.folders {
            files += try SourceTree.files(in: folder, extensions: Self.extensions, minimum: 1, under: root)
        }
        files += Self.rootFiles.map { root.appendingPathComponent($0) }
        return files.filter { !$0.lastPathComponent.hasSuffix(Self.reviewReportSuffix) }
    }

    @Test("every decision cited in code, notes and docs exists in decisions/")
    func citedDecisionsExist() throws {
        let existing = try existingNumbers()
        #expect(existing.count >= 10, "decisions/ holds \(existing.count) records")
        let files = try filesToScan()
        #expect(files.count >= 300, "the scan found only \(files.count) files")
        var dangling: [String] = []
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for number in try citations(in: text) where !existing.contains(number) {
                dangling.append("\(SourceTree.relativePath(file)) cites ADR \(number)")
            }
        }
        #expect(dangling.isEmpty, "\(dangling.sorted().joined(separator: "\n"))")
    }

    @Test("the citation pattern reads a list of numbers and a decisions path")
    func patternReadsLists() throws {
        let sample = "ADRs 0006 and 0007, ADR 0003/0009, see decisions/0011-read-only-surfaces.md and ADR #0012"
        #expect(try citations(in: sample).sorted() == ["0003", "0006", "0007", "0009", "0011", "0012"])
    }

    @Test("every record has a status, the four sections in order, and cites only records that exist")
    func recordsHaveTheReadmeShape() throws {
        let directory = SourceTree.repositoryRoot.appendingPathComponent("decisions")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.range(of: #"^\d{4}-.*\.md$"#, options: .regularExpression) != nil }.sorted()
        let existing = try existingNumbers()
        #expect(names.count >= 10)
        let headings = ["## Context", "## Decision", "## Consequences", "## Docs affected"]
        var problems: [String] = []
        for name in names {
            let text = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
            let number = String(name.prefix(4))
            if !text.hasPrefix("# \(number). ") { problems.append("\(name): the title does not start with its number") }
            if !text.contains("\nStatus: ") { problems.append("\(name): no Status line") }
            var position = text.startIndex
            for heading in headings {
                guard let found = text.range(of: "\n\(heading)\n", range: position..<text.endIndex) else {
                    problems.append("\(name): \(heading) is missing or out of order")
                    break
                }
                position = found.upperBound
            }
            if text.contains("How we got here") { problems.append("\(name): a record carries no history") }
            for cited in try citations(in: text) where !existing.contains(cited) {
                problems.append("\(name) cites ADR \(cited)")
            }
        }
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }

    @Test("the README lists every record, and only the records there are")
    func readmeIndexesTheRecords() throws {
        let directory = SourceTree.repositoryRoot.appendingPathComponent("decisions")
        let readme = try String(contentsOf: directory.appendingPathComponent("README.md"), encoding: .utf8)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.range(of: #"^\d{4}-.*\.md$"#, options: .regularExpression) != nil }
        let linked = Set(readme.matches(of: #/\]\((\d{4}-[a-z0-9-]+\.md)\)/#).map { String($0.output.1) })
        #expect(
            linked == Set(names),
            "README index and decisions/ differ: \(linked.symmetricDifference(names).sorted())"
        )
    }
}
