// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Settings index stays in step with the panes")
struct SettingsIndexDriftTests {
    /// Opening the pane is the whole answer for these: they are the pane itself or its header.
    private static let paneLevel: Set<String> = ["Collections", "Snippets", "Version and build"]

    private func settingsSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("Sources/Features/Settings")
        let shortcutLabels = root.appendingPathComponent("Sources/Core/Runtime/GlobalShortcut.swift")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" } + [shortcutLabels]
        return try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    }

    @Test("every indexed setting still appears in the Settings source, so a rename or removal fails here")
    func everyAnchorExistsInTheSettingsSources() throws {
        let source = try settingsSource()

        let missing = SettingsIndex.entries.filter { !source.contains($0.anchor) }.map(\.title)

        #expect(missing.isEmpty, "not found in Settings sources: \(missing.joined(separator: ", "))")
    }

    @Test("every indexed setting has a row the search can scroll to and flash")
    func everyEntryHasAMarkedRow() throws {
        let source = try settingsSource()

        let unmarked = SettingsIndex.entries
            .filter { !Self.paneLevel.contains($0.title) }
            .filter { !source.contains(".settingsRow(\"\($0.title)\")") }
            .map(\.title)

        #expect(unmarked.isEmpty, "no .settingsRow for: \(unmarked.joined(separator: ", "))")
    }

    @Test("a marked row names a search entry, so a typo does not leave a row that nothing opens")
    func everyMarkedRowIsAnEntry() throws {
        let source = try settingsSource()
        let titles = Set(SettingsIndex.entries.map(\.title))
        let pattern = try NSRegularExpression(pattern: #"\.settingsRow\("([^"]+)"\)"#)
        let range = NSRange(source.startIndex..., in: source)

        let marked = pattern.matches(in: source, range: range).compactMap { match in
            Range(match.range(at: 1), in: source).map { String(source[$0]) }
        }

        #expect(!marked.contains { !titles.contains($0) })
        #expect(Set(marked).count == marked.count, "two rows share a title, so the search cannot tell them apart")
    }
}
