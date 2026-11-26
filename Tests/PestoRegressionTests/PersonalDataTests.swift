// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// The repository is being made public. A home path or the owner's address in a tracked file would sit in the first
/// public commit, and a rewrite of history does not remove what HEAD still holds.
@Suite("Personal data in tracked files")
struct PersonalDataTests {
    private static let forbidden: [String] = [
        "michroyt" + "@",
        "/Users/" + "mich" + "ael" + "royt" + "man",
        "/Users/" + "mroyt" + "man"
    ]

    private static let forbiddenCaseInsensitive: [String] = [
        "steph" + "anie",
        "mich" + "ael's",
        "mich" + "ael’s",
        "royt" + "man",
        "00008140" + "-"
    ]

    /// Standalone first-name check (word boundary so `MichaelRo` GitHub handles are unaffected) and files permitted to
    /// hold the public OSS copyright / author name or common-password dictionary.
    private static let standaloneNamePattern = #"\bmich"# + #"ael\b"#
    private static let publicAttributionAllowed: Set<String> = [
        "LICENSE",
        "Sources/Resources/Info.plist",
        "Sources/Resources/InfoPlist.xcstrings",
        "Sources/Core/Backup/PassphraseStrength.swift",
        "GOVERNANCE.md",
        "CODE_OF_CONDUCT.md",
        "SECURITY.md",
        "THIRD-PARTY-NOTICES.md"
    ]

    private static let folders = [
        "docs", "decisions", "scripts", "Sources", "Tests", ".github", ".githooks", ".claude", "design"
    ]
    private static let extensions: Set<String> = [
        "md", "swift", "sh", "py", "yml", "yaml", "txt", "json", "plist", "",
        "xcstrings", "resolved", "toml", "entitlements", "sdef", "xcprivacy", "env", "jsonl", "svg", "html"
    ]

    @Test("no document, script or source names the owner's email, home folder, family or personal devices")
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

        let standaloneRegex = try NSRegularExpression(pattern: Self.standaloneNamePattern, options: [.caseInsensitive])
        var offenders: [String] = []
        for file in files {
            let relative = SourceTree.relativePath(file)
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for needle in Self.forbidden where text.contains(needle) {
                offenders.append("\(relative): \(needle.prefix(8))…")
            }
            let lowercased = text.lowercased()
            if !Self.publicAttributionAllowed.contains(relative) {
                for needle in Self.forbiddenCaseInsensitive where lowercased.contains(needle) {
                    offenders.append("\(relative): \(needle.prefix(8))…")
                }
                let range = NSRange(text.startIndex..., in: text)
                if standaloneRegex.firstMatch(in: text, range: range) != nil {
                    offenders.append("\(relative): standalone owner name")
                }
            } else {
                for needle in Self.forbiddenCaseInsensitive
                    where needle != "royt" + "man" && lowercased.contains(needle)
                {
                    offenders.append("\(relative): \(needle.prefix(8))…")
                }
            }
        }

        #expect(offenders.isEmpty, "personal data in tracked files: \(offenders.sorted())")
    }
}
