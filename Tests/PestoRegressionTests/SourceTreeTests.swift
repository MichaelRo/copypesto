// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("Source tree helper")
struct SourceTreeTests {
    @Test("a folder that does not exist is an error, not an empty list")
    func missingFolderThrows() {
        #expect(throws: SourceTree.Missing.self) { try SourceTree.swiftFiles(in: "NoSuchFolder", minimum: 1) }
    }

    @Test("a folder with fewer files than expected is an error")
    func tooFewFilesThrows() {
        #expect(throws: SourceTree.Missing.self) { try SourceTree.swiftFiles(in: "CLI", minimum: 1000) }
    }

    @Test("the real folders are found with at least their floor")
    func realFoldersAreFound() throws {
        for (folder, minimum) in SourceTree.minimumFileCounts {
            #expect(try SourceTree.swiftFiles(in: folder, minimum: minimum).count >= minimum)
        }
    }
}
