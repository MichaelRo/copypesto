// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("File structure")
struct OneTypePerFileTests {
    /// Files that hold more than `limit` top-level types today. The list only shrinks: split a file and delete its row,
    /// and the second test makes sure a row that no longer applies is deleted (R-10).
    private static let accepted: Set<String> = [
        "Sources/Core/Security/HistoryLock.swift", "Sources/Core/Runtime/LoginItemService.swift",
        "Sources/Core/Paste/ShelfActions.swift",
        "Sources/Features/Grid/HoverCardPanel.swift", "Sources/Core/Backup/BackupFile.swift",
        "Sources/Features/Settings/BackupSheets.swift", "Sources/Features/Overlay/Announcements.swift",
        "Sources/Features/AI/AIResultPanelController.swift", "Sources/Core/Storage/Undo/UndoChanges.swift",
        "Sources/Core/Storage/RetentionPolicy.swift", "Sources/Core/Storage/CommandBarSuggestions.swift",
        "Sources/Core/Runtime/RuntimeConfiguration.swift", "Sources/Core/Runtime/PerfSignposts.swift",
        "Sources/Core/Runtime/BrandPalette.swift", "Sources/Core/Pasteboard/PasteboardWatcher.swift"
    ]
    private static let limit = 4

    private func topLevelTypeCounts() throws -> [String: Int] {
        let pattern = try NSRegularExpression(
            pattern: #"^(?:public |internal |private |fileprivate |final |indirect )*"#
                + #"(?:struct|class|enum|actor|protocol) \w+"#,
            options: [.anchorsMatchLines]
        )
        var counts: [String: Int] = [:]
        for file in try SourceTree.everySwiftFile() {
            let text = try String(contentsOf: file, encoding: .utf8)
            counts[SourceTree.relativePath(file)] = pattern.numberOfMatches(
                in: text, range: NSRange(text.startIndex..., in: text)
            )
        }
        return counts
    }

    @Test("a file holds at most four top-level types unless it is on the shrinking list")
    func fewTypesPerFile() throws {
        let over = try topLevelTypeCounts().filter { $0.value > Self.limit }.keys.filter { !Self.accepted.contains($0) }
        #expect(over.isEmpty, "split these (one primary type per file, AGENTS.md): \(over.sorted())")
    }

    @Test("the list holds only files that still need splitting")
    func listShrinks() throws {
        let counts = try topLevelTypeCounts()
        let stale = Self.accepted.filter { (counts[$0] ?? 0) <= Self.limit }
        #expect(stale.isEmpty, "delete from the accepted list: \(stale.sorted())")
    }
}
