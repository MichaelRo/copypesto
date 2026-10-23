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
        let found = enumerator.compactMap { $0 as? URL }.filter { extensions.contains($0.pathExtension) }
        guard found.count >= minimum else {
            throw Missing(
                description: "\(relativePath(directory)) holds \(found.count) files, expected at least \(minimum)"
            )
        }
        return found
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

    static let minimumFileCounts: [String: Int] = ["App": 30, "Core": 120, "Features": 60, "Shared": 15, "CLI": 1]
}
