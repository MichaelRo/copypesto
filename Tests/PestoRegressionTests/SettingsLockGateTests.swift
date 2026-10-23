// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// Settings listed clip text, pinned titles and collections while the History Lock was on. The surfaces
/// that render history are wrapped in `HistoryLockGate`; a new one must be wrapped too.
@Suite("Settings and the History Lock")
struct SettingsLockGateTests {
    private static func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent("Sources/Features/Settings").appendingPathComponent(path),
            encoding: .utf8
        )
    }

    @Test("Insights, Snippets, collections and pinned shortcuts sit behind the lock gate")
    func contentSurfacesAreGated() throws {
        #expect(try Self.source("SettingsPanes.swift").contains("HistoryLockGate { InsightsView() }"))
        let collections = try Self.source("CollectionsSettings.swift")
        #expect(collections.contains("HistoryLockGate {\n                    CollectionListView("))
        #expect(collections.contains("HistoryLockGate { SnippetsView("))
        #expect(try Self.source("ShortcutsSettings.swift").contains("HistoryLockGate { PinnedShortcutsSection() }"))
    }

    @Test("every Settings view that prints clip text is one of the gated ones")
    func clipTextIsOnlyInGatedViews() throws {
        let gated: Set = [
            "InsightsView.swift", "SnippetsView.swift", "ShortcutsSettings.swift", "HistoryLockGate.swift"
        ]
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Features/Settings")
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(files.count > 15, "the Settings folder was not found")
        var offenders: [String] = []
        for file in files where !gated.contains(file.lastPathComponent) {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.contains("displayPreviewText") || text
                .contains("gridPreview") { offenders.append(file.lastPathComponent) }
        }
        #expect(offenders.isEmpty, "clip text outside HistoryLockGate: \(offenders)")
    }
}
