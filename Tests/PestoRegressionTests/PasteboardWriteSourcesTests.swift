// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// Every writer that put a secret back on the pasteboard without the concealed marker leaked it to
/// Universal
/// Clipboard and to other clipboard managers. Writes start in `AppState.beginWrite`; the few that deliberately do not
/// are
/// listed here, so a new one is a decision, not an accident.
@Suite("Pasteboard write sites")
struct PasteboardWriteSourcesTests {
    private static let allowed: Set<String> = [
        "AppState+Paste.swift",
        "CopyItemCommand.swift",
        "CopyToPestoIntent.swift",
        "PasteFromPestoIntent.swift"
    ]

    /// `PasteboardProtection.beginWrite` is the one place in Core that clears the board for a write.
    private static let allowedInCore: Set<String> = ["PasteboardProtection.swift"]

    @Test("only the listed files clear the pasteboard directly")
    func clearContentsIsConfined() throws {
        var scanned = 0
        var offenders: [String] = []
        for (folder, minimum) in [("App", 30), ("Features", 60), ("Shared", 15)] {
            for file in try SourceTree.swiftFiles(in: folder, minimum: minimum) {
                scanned += 1
                let text = try String(contentsOf: file, encoding: .utf8)
                if text.contains(".clearContents()"), !Self.allowed.contains(file.lastPathComponent) {
                    offenders.append(file.lastPathComponent)
                }
            }
        }
        for (folder, minimum) in [("Core", 200), ("CLI", 1)] {
            for file in try SourceTree.swiftFiles(in: folder, minimum: minimum) {
                scanned += 1
                let text = try String(contentsOf: file, encoding: .utf8)
                if text.contains(".clearContents()"), !Self.allowedInCore.contains(file.lastPathComponent) {
                    offenders.append(file.lastPathComponent)
                }
            }
        }
        #expect(scanned > 100, "the sources were not found")
        #expect(offenders.isEmpty, "use AppState.beginWrite so a secret keeps its protection: \(offenders)")
    }
}
