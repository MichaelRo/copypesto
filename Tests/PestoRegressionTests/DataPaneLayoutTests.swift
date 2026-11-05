// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("The Data pane keeps Backup and Sync as two adjacent cards at the top (ADR 0022)")
struct DataPaneLayoutTests {
    private func source(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent("Sources/Features/Settings/\(name)"), encoding: .utf8
        )
    }

    private func collapsed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    @Test("the pane opens with the Backup and Sync group, before History and every other section")
    func whenPaneIsBuilt_thenBackupAndSyncComeFirst() throws {
        let pane = try collapsed(source("SettingsPanes.swift"))
        let start = try #require(pane.range(of: "struct DataPane: View"))
        let form = try #require(pane.range(of: "Form {", range: start.upperBound..<pane.endIndex))

        let first = pane[form.upperBound...].trimmingCharacters(in: .whitespaces)

        #expect(first.hasPrefix("BackupSettings()"), "the Data pane no longer opens with BackupSettings()")
    }

    @Test("Sync is its own section, directly after the Backup section, with nothing between them")
    func whenCardsAreBuilt_thenSyncFollowsBackupAsASeparateSection() throws {
        let body = try collapsed(source("BackupSettings.swift"))
        let backupHeader = try #require(body.range(of: "Text(\"Backup\").settingsRow(\"Backup\")"))
        let syncRows = try #require(body.range(of: "SyncRows(", range: backupHeader.upperBound..<body.endIndex))
        let between = body[backupHeader.upperBound..<syncRows.lowerBound]

        let sections = between.components(separatedBy: "Section {").count - 1

        #expect(sections == 1, "expected exactly the Sync section between the Backup header and SyncRows")
        #expect(body.contains("Text(\"Sync\")"), "the Sync card lost its header")
        #expect(!between.contains("Divider()"))
    }
}
