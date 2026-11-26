// SPDX-License-Identifier: MIT
import Foundation

enum SourceTree {
    struct Missing: Error, CustomStringConvertible {
        let description: String
    }

    static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    static var sources: URL {
        repositoryRoot.appendingPathComponent("Sources")
    }

    static func relativePath(_ file: URL) -> String {
        file.path.replacingOccurrences(of: repositoryRoot.path + "/", with: "")
    }

    /// Throws when the folder is missing or holds fewer than `minimum` matching files, so a scan test that cannot
    /// find its input fails instead of passing over nothing.
    static func files(
        in folder: String,
        extensions: Set<String> = ["swift"],
        minimum: Int,
        under base: URL = sources
    ) throws
    -> [URL] {
        let directory = base.appendingPathComponent(folder)
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            throw Missing(description: "\(relativePath(directory)) does not exist")
        }
        let found = enumerator.compactMap { $0 as? URL }.filter {
            !isInNestedWorktree($0) && extensions.contains($0.pathExtension)
        }
        guard found.count >= minimum else {
            throw Missing(
                description: "\(relativePath(directory)) holds \(found.count) files, expected at least \(minimum)"
            )
        }
        return found
    }

    /// The paths (relative to the checkout) that git ignores, such as `CLAUDE.local.md` and `.claude/*.local.json`:
    /// they are the person's own files and never committed, so a scan of what the repository publishes skips them.
    /// A path that is tracked is never reported, even if a pattern matches it. Empty when git cannot answer (no git,
    /// or a copy of the sources outside a checkout), so the scan then reads everything.
    static func ignoredByGit(_ relativePaths: [String]) -> Set<String> {
        guard !relativePaths.isEmpty else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", repositoryRoot.path, "check-ignore", "--stdin", "-z"]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        input.fileHandleForWriting.write(Data(relativePaths.joined(separator: "\u{0}").utf8 + [0]))
        try? input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        // 0: some paths are ignored, 1: none are; anything else is git failing to answer.
        guard process.terminationStatus == 0 || process.terminationStatus == 1 else { return [] }
        return Set(data.split(separator: 0).compactMap { String(data: Data($0), encoding: .utf8) })
    }

    /// Agent worktrees live under the checkout's own `.claude/worktrees/`, and a scan must not read their copies. Only
    /// the part of the path below this checkout counts: a checkout that is itself such a worktree still scans itself.
    static func isInNestedWorktree(_ file: URL) -> Bool {
        relativePath(file).contains(".claude/worktrees/")
    }

    static func everySwiftFile(minimum: Int = 280) throws -> [URL] {
        try files(in: "", minimum: minimum)
    }

    static func swiftFiles(in folder: String, minimum: Int) throws -> [URL] {
        try files(in: folder, minimum: minimum)
    }

    static func allSwiftFiles(in folders: [String: Int]) throws -> [URL] {
        try folders.sorted { $0.key < $1.key }.flatMap { try swiftFiles(in: $0.key, minimum: $0.value) }
    }

    static let minimumFileCounts: [String: Int] = [
        "App": 30, "Core": 120, "Features": 60, "Shared": 15, "CLI": 1, "Mobile": 3, "MobileShare": 3,
        "MobileAutoFill": 2, "MobileKeyboard": 4, "MobileWidget": 2, "Widget": 10
    ]
}
