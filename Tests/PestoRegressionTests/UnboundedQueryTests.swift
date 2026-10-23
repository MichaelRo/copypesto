// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("Live queries over the history")
struct UnboundedQueryTests {
    /// The shelf filters sealed fields in memory, so it needs every clip, and gets them from `HistoryStore`, not a
    /// query.
    /// The quick menu sets its five-clip descriptor in `init` (`QuickMenuTests` pins it).
    private static let mayQueryEveryClip: Set<String> = ["QuickMenuView.swift"]

    @Test(
        "no view holds a live query over every clip: the shelf reads HistoryStore, the rest bound the fetch"
    )
    func noViewButTheShelfQueriesEveryClip() throws {
        var offenders: [String] = []
        for file in try SourceTree.swiftFiles(in: "Features", minimum: 60)
            where !Self.mayQueryEveryClip.contains(file.lastPathComponent)
        {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (number, line) in text.components(separatedBy: "\n").enumerated()
                where Self.isUnboundedClipQuery(line)
            {
                offenders.append("\(file.lastPathComponent):\(number + 1)")
            }
        }

        #expect(offenders.isEmpty, "an unbounded @Query over ClipboardItem: \(offenders.joined(separator: ", "))")
    }

    @Test("the scan recognises a query with no filter and no descriptor")
    func scanRecognisesTheShapes() {
        #expect(Self
            .isUnboundedClipQuery("    @Query(sort: \\ClipboardItem.timestamp) private var items: [ClipboardItem]"))
        #expect(Self.isUnboundedClipQuery("    @Query private var items: [ClipboardItem]"))
        #expect(!Self
            .isUnboundedClipQuery(
                "    @Query(filter: #Predicate<ClipboardItem> { $0.isPinned }) private var p: [ClipboardItem]"
            ))
        #expect(!Self.isUnboundedClipQuery("    @Query(Self.recent) private var items: [ClipboardItem]"))
        #expect(!Self.isUnboundedClipQuery("    @Query(View.candidatesDescriptor) private var items: [ClipboardItem]"))
        #expect(!Self.isUnboundedClipQuery("    @Query(sort: \\Pinboard.sortOrder) private var pinboards: [Pinboard]"))
    }

    private static func isUnboundedClipQuery(_ line: String) -> Bool {
        let code = line.trimmingCharacters(in: .whitespaces)
        guard !code.hasPrefix("//"), code.contains("@Query"), code.contains("ClipboardItem") else { return false }
        return !code.contains("filter:") && !code.contains("@Query(Self.")
            && !code.contains("Descriptor")
    }
}
