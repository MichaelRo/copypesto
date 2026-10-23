// SPDX-License-Identifier: MIT
import Foundation

/// Files are stored as the file URLs themselves, one per line: Pesto keeps the path, never the file's contents.
public enum FileClip {
    public struct Summary: Equatable, Sendable {
        public let title: String
        public let subtitle: String
        public let count: Int
    }

    public static func encode(_ urls: [URL]) -> String {
        urls.map(\.absoluteString).joined(separator: "\n")
    }

    public static func urls(from text: String) -> [URL] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let url = URL(string: line.trimmingCharacters(in: .whitespaces)), url.isFileURL else { return nil }
            return url
        }
    }

    /// The files Show in Finder can select: the ones still on disk, at most `limit` so a huge drop costs a few checks.
    public static func revealable(inText text: String, limit: Int = 50, exists: (URL) -> Bool) -> [URL] {
        Array(urls(from: text).prefix(limit).filter(exists))
    }

    /// The file, when the clip is one GIF: the card plays it instead of showing a still icon.
    public static func animatedPictureURL(inText text: String) -> URL? {
        let files = urls(from: text)
        guard files.count == 1, let file = files.first, file.pathExtension.lowercased() == "gif" else { return nil }
        return file
    }

    public static func summary(of text: String) -> Summary {
        let urls = urls(from: text)
        guard let first = urls.first else { return Summary(title: text, subtitle: "", count: 0) }
        if urls.count == 1 {
            let folder = first.deletingLastPathComponent().lastPathComponent
            return Summary(title: first.lastPathComponent, subtitle: folder, count: 1)
        }
        let shown = urls.prefix(2).map(\.lastPathComponent).joined(separator: ", ")
        let subtitle = urls.count <= 2 ? shown : String(localized: "\(shown) and \(urls.count - 2) more")
        return Summary(title: String(localized: "\(urls.count) files"), subtitle: subtitle, count: urls.count)
    }

    public static func spokenDescription(of text: String, missingCount: Int) -> String {
        let summary = summary(of: text)
        let spoken = switch (summary.count, summary.subtitle.isEmpty) {
        case (1, true): summary.title
        case (1, false): "\(summary.title) in \(summary.subtitle)"
        default: "\(summary.title): \(summary.subtitle)"
        }
        guard missingCount > 0 else { return spoken }
        return spoken + (summary.count > 1 ? ", \(missingCount) moved or deleted" : ", moved or deleted")
    }

    public static func missing(
        in urls: [URL],
        exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    )
        -> [URL]
    {
        urls.filter { !exists($0.path) }
    }

    /// True when none of the first `limit` files exists: a paste would hand the target app only dead paths. A bounded
    /// look, so a huge drop costs a few `stat` calls and a stalled volume is not waited on for every file.
    public static func isGone(
        _ urls: [URL],
        limit: Int = 50,
        exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    )
        -> Bool
    {
        let checked = urls.prefix(limit)
        return !checked.isEmpty && !checked.contains { exists($0.path) }
    }

    /// The same check off the main thread: a file on a stalled network volume can make `stat` wait for seconds, and a
    /// card must never do that while it draws.
    public static func missing(inText text: String) async -> [URL] {
        await Task.detached(priority: .utility) { missing(in: urls(from: text)) }.value
    }

    public static func isFolder(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}
