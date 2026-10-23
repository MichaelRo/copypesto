// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// `PestoCore` is one module, so nothing stops a directory from reaching into another in both directions. Storage and
/// Pasteboard, Runtime and almost everything, still do (ADR 0007). A storage or model module becomes mechanical only
/// once the directories form a one-way graph, so this test lets the list of edges between directories shrink and never
/// grow: a new reference from one directory's types into another's fails here until it is moved or argued for.
/// `Model` holds the value types the others share and depends on nothing; reaching into it is always allowed, so those
/// edges are not listed.
@Suite("Directories of PestoCore")
struct CoreDirectoryCycleTests {
    /// Each "A->B" is a type declared in B and named in A. Delete a line when its last reference goes.
    private static let allowedEdges: Set<String> = [
        "AI->Imaging",
        "AI->Runtime",
        "Backup->Runtime",
        "Crypto->Runtime",
        "Import->Crypto",
        "Import->Paste",
        "Import->Pasteboard",
        "Import->Runtime",
        "Import->Storage",
        "Intelligence->Predicate",
        "Paste->Pasteboard",
        "Paste->Runtime",
        "Paste->Storage",
        "Pasteboard->Imaging",
        "Pasteboard->Runtime",
        "Search->AI",
        "Security->Runtime",
        "Security->Storage",
        "Seeding->Pasteboard",
        "Seeding->Runtime",
        "Storage->AI",
        "Storage->Backup",
        "Storage->Crypto",
        "Storage->Imaging",
        "Storage->Pasteboard",
        "Storage->Predicate",
        "Storage->Runtime",
        "Storage->Search",
        "Storage->Sync",
        "Sync->Crypto",
        "Sync->Runtime"
    ]

    private func edges() throws -> Set<String> {
        let root = SourceTree.sources.appendingPathComponent("Core")
        let folders = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(
                    atPath: root.appendingPathComponent($0).path, isDirectory: &isDirectory
                ) && isDirectory.boolValue
            }
        var sources: [CoreDependencyScan.Source] = []
        for folder in folders {
            for file in try SourceTree.files(in: folder, minimum: 1, under: root) {
                try sources.append(.init(folder: folder, text: String(contentsOf: file, encoding: .utf8)))
            }
        }
        return CoreDependencyScan.edges(sources)
    }

    @Test("no directory reaches into another that the list does not already name")
    func noNewEdges() throws {
        let found = try edges()

        #expect(found.count > 10, "the scan found almost nothing: the sources were not read")
        #expect(
            found.subtracting(Self.allowedEdges).isEmpty,
            "new dependencies between Core directories: \(found.subtracting(Self.allowedEdges).sorted())"
        )
    }

    @Test("an edge that is gone comes off the list, so the list only shrinks")
    func noStaleEdges() throws {
        let stale = try Self.allowedEdges.subtracting(edges())

        #expect(stale.isEmpty, "remove from allowedEdges: \(stale.sorted())")
    }

    @Test("the directories form a one-way graph: no loop of any length")
    func edgesFormNoCycle() throws {
        #expect(try CoreDependencyScan.cycle(in: edges()) == nil, "directories depend on each other in a loop")
    }

    @Test("Model, the value types everything shares, depends on no other directory")
    func modelIsALeaf() throws {
        #expect(try !edges().contains { $0.hasPrefix("Model->") })
    }
}
