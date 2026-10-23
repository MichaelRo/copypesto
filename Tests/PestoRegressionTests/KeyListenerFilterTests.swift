// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("Global key listeners")
struct KeyListenerFilterTests {
    private static let allowedGlobalKeyDownFiles: Set<String> = [
        "AppDelegate+Capture.swift",
        "QuickMenuWindowController.swift",
        "StackPasteSession.swift"
    ]

    @Test("only the three documented files install a global keyDown monitor, and each filters to its single key")
    func whenScanningForGlobalKeyDownMonitors_thenOnlyDocumentedListenersExistAndFilterKeys() throws {
        let files = try SourceTree.allSwiftFiles(in: SourceTree.minimumFileCounts)
        var globalKeyMonitors: [String] = []

        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.contains("addGlobalMonitorForEvents(matching: .keyDown)") {
                globalKeyMonitors.append(file.lastPathComponent)
            }
        }

        #expect(
            Set(globalKeyMonitors) == Self.allowedGlobalKeyDownFiles,
            "unexpected global keyDown monitor in: \(globalKeyMonitors)"
        )

        let doubleCopy = try String(
            contentsOf: SourceTree.sources.appendingPathComponent("App/AppDelegate+Capture.swift"),
            encoding: .utf8
        )
        #expect(doubleCopy.contains("guard event.keyCode == 8, modifiers == .command else { return }"))

        let quickMenu = try String(
            contentsOf: SourceTree.sources.appendingPathComponent("Features/Overlay/QuickMenuWindowController.swift"),
            encoding: .utf8
        )
        #expect(quickMenu.contains("private static let escapeKeyCode: UInt16 = 53"))
        #expect(quickMenu.contains("guard event.keyCode == Self.escapeKeyCode else { return }"))

        let stackSession = try String(
            contentsOf: SourceTree.sources.appendingPathComponent("Core/Paste/StackPasteSession.swift"),
            encoding: .utf8
        )
        #expect(stackSession.contains("StackKeyPolicy.isUserPaste("))
    }
}
