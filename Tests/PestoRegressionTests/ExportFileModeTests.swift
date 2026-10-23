// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("A file Pesto writes with clip text in it is owner-only")
struct ExportFileModeTests {
    @Test("the text export goes through PrivateFile, not a plain Data.write")
    func whenExporting_thenOwnerOnly() throws {
        let file = try #require(
            SourceTree.swiftFiles(in: "Features/Settings", minimum: 20)
                .first { $0.lastPathComponent == "DataSettings.swift" }
        )
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("PrivateFile.write("), "the export must be written owner-only")
        #expect(!text.contains("data.write(to:"), "a plain Data.write leaves the file readable by the group and others")
    }

    @Test("performance signposts never log a clip id publicly")
    func whenSignposting_thenDetailIsPrivate() throws {
        let file = SourceTree.sources.appendingPathComponent("Core/Runtime/PerfSignposts.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(!text.contains("privacy: .public"), "the event detail carries a clip id")
    }
}
