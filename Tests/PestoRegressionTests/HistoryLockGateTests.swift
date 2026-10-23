// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// Every way in to the history (Shortcuts, AppleScript, `pesto://`) must ask whether the history is locked first.
@Suite("History lock gates")
struct HistoryLockGateTests {
    private func text(_ relative: String) throws -> String {
        try String(contentsOf: SourceTree.sources.appendingPathComponent(relative), encoding: .utf8)
    }

    @Test("an intent or AppleScript command that reads the store also checks the lock")
    func storeReadersCheckTheLock() throws {
        let files = try SourceTree.swiftFiles(in: "Features/Intents", minimum: 3)
            + SourceTree.swiftFiles(in: "App/AppleScript", minimum: 3)
        var offenders: [String] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let touchesHistory = source.contains("modelContainer") || source.contains("historyContainer")
                || source.contains("pasteItem")
            let isPlumbing = file.lastPathComponent == "ScriptingContext.swift"
            let checksLock = source.contains("historyIsAccessible") || source.contains("isHistoryLockedNow")
            if touchesHistory, !isPlumbing, !checksLock { offenders.append(file.lastPathComponent) }
        }

        #expect(offenders.isEmpty, "these read history without checking the lock: \(offenders)")
    }

    @Test("nothing puts a clip into Spotlight (ADR 0002)")
    func nothingIndexesClips() throws {
        for file in try SourceTree.everySwiftFile() where file.lastPathComponent != "SpotlightCleanup.swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(!source.contains("indexSearchableItems"), "\(file.lastPathComponent) indexes into Spotlight")
        }
    }
}
