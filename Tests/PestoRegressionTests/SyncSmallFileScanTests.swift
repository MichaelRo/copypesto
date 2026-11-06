// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("Only segments and payload files are read whole from a sync folder")
struct SyncSmallFileScanTests {
    private static let allowed: Set<String> = [
        "SyncFolderService.swift", "SyncFolderService+Compaction.swift", "SyncGroupSurvey.swift", "SyncSmallFile.swift"
    ]

    @Test("a vault, device record, grant, join request or identity is read through SyncSmallFile")
    func smallFilesGoThroughTheCap() throws {
        var files = try SourceTree.swiftFiles(in: "Core/Sync", minimum: 8)
        files += try SourceTree.swiftFiles(in: "Core/Storage/Sync", minimum: 8)
        var offenders: [String] = []
        for file in files where !Self.allowed.contains(file.lastPathComponent) {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.contains("Data(contentsOf:") { offenders.append(SourceTree.relativePath(file)) }
        }
        #expect(offenders.isEmpty, "\(offenders.sorted())")
    }
}
