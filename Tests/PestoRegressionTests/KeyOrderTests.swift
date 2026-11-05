// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("Shortcuts are written in the Mac's order: ⌃ ⌥ ⇧ ⌘, then the key")
struct KeyOrderTests {
    private static let order: [Character: Int] = ["⌃": 0, "⌥": 1, "⇧": 2, "⌘": 3]

    /// Runs of two or more modifier symbols that are not in the Mac's order.
    static func outOfOrder(in text: String) -> [String] {
        var runs: [String] = []
        var current = ""
        func close() {
            let keys = Array(current)
            let sorted = keys.sorted { (order[$0] ?? 0) < (order[$1] ?? 0) }
            if keys.count > 1, keys != sorted { runs.append(current) }
            current = ""
        }
        for character in text {
            if order[character] != nil { current.append(character) } else { close() }
        }
        close()
        let words = text.components(separatedBy: "Command-Shift").count - 1
        return runs + Array(repeating: "Command-Shift", count: words)
    }

    @Test("the check itself tells the two orders apart")
    func theCheckFlagsOnlyTheWrongOrder() {
        #expect(Self.outOfOrder(in: "Press ⌘⇧V.") == ["⌘⇧"])
        #expect(Self.outOfOrder(in: "⌘⌥V and ⌘⌃Q") == ["⌘⌥", "⌘⌃"])
        #expect(Self.outOfOrder(in: "Press ⇧⌘V, or ⌃⌥⇧⌘V, or ⌘V, or ⌃1.").isEmpty)
        #expect(Self.outOfOrder(in: "Command-Shift-V") == ["Command-Shift"])
        #expect(Self.outOfOrder(in: "Shift-Command-V").isEmpty)
    }

    @Test("no source file, guide or doc writes a shortcut in another order")
    func everyShortcutIsInTheMacsOrder() throws {
        let root = SourceTree.repositoryRoot
        var files = try SourceTree.everySwiftFile()
        files += try SourceTree.files(in: "Tests", minimum: 100, under: root)
        files += try SourceTree.files(in: "docs/guide", extensions: ["md"], minimum: 5, under: root)
        files += ["README.md", "AGENTS.md", "CONTRIBUTING.md", "docs/feature-reference.md", "docs/copy-guide.md"]
            .map { root.appendingPathComponent($0) }
        var offenders: [String] = []
        var seen = 0
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            if file.lastPathComponent == "KeyOrderTests.swift" { continue }
            if text.contains(where: { Self.order[$0] != nil }) { seen += 1 }
            for run in Self.outOfOrder(in: text) {
                offenders.append("\(SourceTree.relativePath(file)): \(run)")
            }
        }

        #expect(seen > 20, "the scan found almost no shortcuts, so it is looking in the wrong place")
        #expect(offenders.isEmpty, "write ⇧⌘V, not ⌘⇧V: \(offenders.joined(separator: "; "))")
    }
}
