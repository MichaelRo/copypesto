// SPDX-License-Identifier: MIT
import Foundation

/// The Clip Inspector's rules for what it saves (ADR 0071): a blank title or note is none, a tag is typed without its
/// `@` (the Mac's search) or `#` (iOS), kept once whatever its case, and several may be typed at once separated by
/// commas.
public enum ClipDetailsEdit {
    public static func title(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func note(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func adding(_ typed: String, to tags: [String]) -> [String] {
        var result = tags
        for part in typed.split(separator: ",") {
            var tag = part.trimmingCharacters(in: .whitespaces)
            while tag.hasPrefix("@") || tag.hasPrefix("#") {
                tag.removeFirst()
            }
            guard !tag.isEmpty, !result.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else {
                continue
            }
            result.append(tag)
        }
        return result
    }

    public static func removing(_ tag: String, from tags: [String]) -> [String] {
        tags.filter { $0.caseInsensitiveCompare(tag) != .orderedSame }
    }
}
