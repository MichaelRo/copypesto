// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("A clip dragged to the Desktop arrives as a file")
struct DragFileTests {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pesto-dragtest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("the file is written owner-only, in a folder the sweep recognises")
    func whenWritten_thenPrivateAndSweepable() throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = try #require(DragFile.write(Data("hello".utf8), named: "Note.txt", in: directory))

        #expect(file.deletingLastPathComponent().lastPathComponent.hasPrefix(DragFile.folderPrefix))
        #expect(try String(contentsOf: file, encoding: .utf8) == "hello")
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        let folderMode = try FileManager.default.attributesOfItem(
            atPath: file.deletingLastPathComponent().path
        )[.posixPermissions] as? Int
        #expect(folderMode == 0o700)
    }

    @Test("two drags never share a folder")
    func whenTwoDrags_thenTwoFolders() throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try #require(DragFile.write(Data("a".utf8), named: "x.txt", in: directory))
        let second = try #require(DragFile.write(Data("b".utf8), named: "x.txt", in: directory))

        #expect(first.deletingLastPathComponent() != second.deletingLastPathComponent())
    }

    @Test("the name is the clip's title, or a dated name, plus its extension, and cannot escape the folder")
    func whenNamed_thenSafe() {
        #expect(DragFile.fileName(title: "Recipe", date: .now, fileExtension: "txt") == "Recipe.txt")
        #expect(DragFile.fileName(title: "../../etc/passwd", date: .now, fileExtension: "txt").contains("/") == false)
        #expect(DragFile.fileName(title: nil, date: .now, fileExtension: "png").hasPrefix("Pesto picture "))
    }
}
