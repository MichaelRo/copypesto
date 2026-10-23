// SPDX-License-Identifier: MIT
import Foundation

public struct ImportedSnippet: Equatable, Sendable {
    public let name: String?
    public let text: String
}

/// What a snippets file held. Raycast exports snippets as a JSON array of `{name, text, keyword}`, and the converters
/// for TextExpander and Alfred write the same, so one reader serves all three.
public struct SnippetPack: Equatable, Sendable {
    /// Snippets with a placeholder Pesto fills in, ready to add.
    public let snippets: [ImportedSnippet]
    /// Entries with no placeholder: kept as pinned clips, not listed as snippets.
    public let plainText: [ImportedSnippet]
    /// Entries that use something Pesto does not fill in (the selection, a custom date format); the token is left as
    /// typed.
    public let withUnsupportedTokens: Int
    /// Entries left out: empty, or longer than a snippet can be.
    public let skipped: Int
}

public enum SnippetPackReader {
    public enum ReadError: Error, Equatable, Sendable {
        case tooLarge
        case notASnippetFile
    }

    public static let maxBytes = 5_000_000
    public static let maxEntries = 1000
    public static let maxTextLength = 20_000

    public static func read(_ data: Data) throws -> SnippetPack {
        guard data.count <= maxBytes else { throw ReadError.tooLarge }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { throw ReadError.notASnippetFile }
        let entries: [[String: Any]]
        if let array = object as? [[String: Any]] {
            entries = array
        } else if let wrapped = (object as? [String: Any])?["snippets"] as? [[String: Any]] {
            entries = wrapped
        } else {
            throw ReadError.notASnippetFile
        }

        var snippets: [ImportedSnippet] = []
        var plain: [ImportedSnippet] = []
        var unsupported = 0
        var skipped = 0
        for entry in entries.prefix(maxEntries) {
            guard let raw = entry["text"] as? String,
                  !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  raw.count <= maxTextLength else
            {
                skipped += 1
                continue
            }
            let name = (entry["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            if usesUnsupportedToken(raw) { unsupported += 1 }
            let text = convertingPlaceholders(raw)
            let imported = ImportedSnippet(name: name, text: text)
            if SnippetDraft.evaluate(text) == .ready { snippets.append(imported) } else { plain.append(imported) }
        }
        skipped += max(0, entries.count - maxEntries)
        return SnippetPack(snippets: snippets, plainText: plain, withUnsupportedTokens: unsupported, skipped: skipped)
    }

    /// Raycast writes `{date}`; Pesto writes `{{date}}`. Text that already has double braces is left alone.
    static func convertingPlaceholders(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"(?<!\{)\{(date|time|datetime|cursor|clipboard|uuid)\}(?!\})"#, with: "{{$1}}",
            options: .regularExpression
        )
    }

    private static func usesUnsupportedToken(_ text: String) -> Bool {
        let tokens = #"selection|selected text|day|month|year|(date|time|datetime) [^}]+"#
        return text.range(of: #"(?<!\{)\{("# + tokens + #")[^}]*\}(?!\})"#, options: .regularExpression) != nil
    }
}
