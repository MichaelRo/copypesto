// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// Every pull request adds strings to the one String Catalog and a row to the ADR index, so parallel branches used to
/// conflict there on every merge (2026-11-25: five rounds of conflicts). `.gitattributes` names a merge for each, and
/// `scripts/merge-xcstrings.py` merges a catalog entry by entry (docs/development.md, "Merging").
@Suite("Merging the String Catalog and the ADR index")
struct MergeDriverTests {
    private let root = SourceTree.repositoryRoot

    private func run(_ base: [String: Any], _ ours: [String: Any], _ theirs: [String: Any]) throws
        -> (status: Int32, merged: [String: Any])
    {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("merge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var paths: [String] = []
        for (name, strings) in [("base", base), ("ours", ours), ("theirs", theirs)] {
            let url = folder.appendingPathComponent("\(name).xcstrings")
            let document: [String: Any] = ["sourceLanguage": "en", "strings": strings, "version": "1.0"]
            try JSONSerialization.data(withJSONObject: document).write(to: url)
            paths.append(url.path)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", root.appendingPathComponent("scripts/merge-xcstrings.py").path] + paths
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let data = try Data(contentsOf: URL(fileURLWithPath: paths[1]))
        let merged = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return (process.terminationStatus, merged["strings"] as? [String: Any] ?? [:])
    }

    @Test("strings each branch added, changed or removed are all kept as that branch left them")
    func whenBranchesTouchDifferentKeys_thenTheyMerge() throws {
        let base: [String: Any] = ["Shared": ["v": 1], "Gone": ["v": 1], "Edited": ["v": 1]]
        let ours: [String: Any] = ["Shared": ["v": 1], "Gone": ["v": 1], "Edited": ["v": 2], "Ours": ["v": 1]]
        let theirs: [String: Any] = ["Shared": ["v": 1], "Edited": ["v": 1], "Theirs": ["v": 1]]
        let result = try run(base, ours, theirs)
        #expect(result.status == 0)
        #expect(Set(result.merged.keys) == ["Shared", "Edited", "Ours", "Theirs"])
        #expect((result.merged["Edited"] as? [String: Int])?["v"] == 2)
    }

    @Test("a string both branches changed differently is a real conflict and is left to a person")
    func whenBothChangeOneKey_thenConflict() throws {
        let result = try run(["Key": ["v": 1]], ["Key": ["v": 2]], ["Key": ["v": 3]])
        #expect(result.status == 1)
    }

    @Test(".gitattributes names both merges and the Makefile registers the catalog's driver")
    func whenCloned_thenTheDriversAreNamed() throws {
        let attributes = try String(contentsOf: root.appendingPathComponent(".gitattributes"), encoding: .utf8)
        #expect(attributes.contains("decisions/README.md merge=union"))
        #expect(attributes.contains("*.xcstrings merge=xcstrings"))
        let makefile = try String(contentsOf: root.appendingPathComponent("Makefile"), encoding: .utf8)
        #expect(makefile.contains(#"git config merge.xcstrings.driver "python3 scripts/merge-xcstrings.py %O %A %B""#))
    }
}
