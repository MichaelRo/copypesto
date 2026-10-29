// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// The repository is being made public. A home path or the owner's address in a tracked file would sit in the first
/// public commit, and a rewrite of history does not remove what HEAD still holds.
@Suite("Personal data in tracked files")
struct PersonalDataTests {
    private static let forbidden: [String] = [
        "michroyt" + "@",
        "/Users/" + "michaelroytman",
        "/Users/" + "mroytman"
    ]

    private static let folders = ["docs", "decisions", "scripts", "Sources", "Tests", ".github", ".githooks"]
    private static let extensions: Set<String> = ["md", "swift", "sh", "py", "yml", "yaml", "txt", "json", "plist", ""]

    @Test("no document, script or source names the owner's email or a home folder")
    func noPersonalDataInTrackedFiles() throws {
        var files: [URL] = []
        for folder in Self.folders {
            files += try SourceTree.files(
                in: folder, extensions: Self.extensions, minimum: 1, under: SourceTree.repositoryRoot
            )
        }
        let top = try FileManager.default.contentsOfDirectory(
            at: SourceTree.repositoryRoot, includingPropertiesForKeys: nil
        )
        // In a git worktree `.git` is a file holding the path of the main checkout: not a tracked file.
        files += top.filter {
            $0
                .lastPathComponent != ".git" &&
                (Self.extensions.contains($0.pathExtension) || $0.lastPathComponent == "Makefile")
        }

        var offenders: [String] = []
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for needle in Self.forbidden where text.contains(needle) {
                offenders.append("\(SourceTree.relativePath(file)): \(needle.prefix(8))…")
            }
        }

        #expect(offenders.isEmpty, "personal data in tracked files: \(offenders.sorted())")
    }
}
