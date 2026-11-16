// SPDX-License-Identifier: MIT
import Foundation

/// Converts a Markdown document into a structured JSON array of blocks (`heading`, `list`, `code`, `quote`,
/// `paragraph`) for Paste As… / Copy As… JSON.
public enum MarkdownJSON {
    public static let maxInputBytes = 1_000_000

    public static func convert(_ text: String) -> String? {
        guard text.utf8.count <= maxInputBytes else { return nil }
        let blocks = parseBlocks(text)
        guard !blocks.isEmpty else { return nil }
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? JSONSerialization.data(withJSONObject: blocks, options: options) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func parseBlocks(_ text: String) -> [[String: Any]] {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        var blocks: [[String: Any]] = []
        var index = 0
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
            } else if trimmed.hasPrefix("```") {
                blocks.append(readCodeBlock(lines: lines, index: &index, opening: trimmed))
            } else if let heading = parseHeading(trimmed) {
                blocks.append(["type": "heading", "level": heading.level, "text": heading.text])
                index += 1
            } else if trimmed.hasPrefix(">") {
                blocks.append(readQuoteBlock(lines: lines, index: &index))
            } else if let listStart = parseListItem(trimmed) {
                blocks.append(readListBlock(lines: lines, index: &index, ordered: listStart.ordered))
            } else {
                blocks.append(readParagraphBlock(lines: lines, index: &index))
            }
        }
        return blocks
    }

    private static func readCodeBlock(lines: [String], index: inout Int, opening: String) -> [String: Any] {
        let language = String(opening.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        var codeLines: [String] = []
        index += 1
        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                index += 1
                break
            }
            codeLines.append(lines[index])
            index += 1
        }
        var entry: [String: Any] = ["type": "code", "text": codeLines.joined(separator: "\n")]
        if !language.isEmpty { entry["language"] = language }
        return entry
    }

    private static func readQuoteBlock(lines: [String], index: inout Int) -> [String: Any] {
        var quoteLines: [String] = []
        while index < lines.count {
            let current = lines[index].trimmingCharacters(in: .whitespaces)
            guard current.hasPrefix(">") else { break }
            quoteLines.append(String(current.dropFirst()).trimmingCharacters(in: .whitespaces))
            index += 1
        }
        return ["type": "quote", "text": quoteLines.joined(separator: "\n")]
    }

    private static func readListBlock(lines: [String], index: inout Int, ordered: Bool) -> [String: Any] {
        var items: [String] = []
        while index < lines.count {
            let current = lines[index].trimmingCharacters(in: .whitespaces)
            guard let next = parseListItem(current), next.ordered == ordered else { break }
            items.append(next.text)
            index += 1
        }
        return ["type": "list", "ordered": ordered, "items": items]
    }

    private static func readParagraphBlock(lines: [String], index: inout Int) -> [String: Any] {
        var paragraphLines: [String] = []
        while index < lines.count {
            let current = lines[index].trimmingCharacters(in: .whitespaces)
            let startsBlock = current.isEmpty || current.hasPrefix("```") || current.hasPrefix(">")
                || parseHeading(current) != nil || parseListItem(current) != nil
            if startsBlock, !paragraphLines.isEmpty { break }
            paragraphLines.append(current)
            index += 1
        }
        return ["type": "paragraph", "text": paragraphLines.joined(separator: " ")]
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }
        guard !hashes.isEmpty, hashes.count <= 6 else { return nil }
        let rest = line.dropFirst(hashes.count)
        guard rest.first == " " || rest.first == "\t" else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (hashes.count, text)
    }

    private static func parseListItem(_ line: String) -> (ordered: Bool, text: String)? {
        if let first = line.first, "-*+".contains(first), line.dropFirst().first == " " {
            let text = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : (false, text)
        }
        let digits = line.prefix(while: \.isNumber)
        if !digits.isEmpty, digits.count <= 3 {
            let afterDigits = line.dropFirst(digits.count)
            if afterDigits.first == ".", afterDigits.dropFirst().first == " " {
                let text = afterDigits.dropFirst(2).trimmingCharacters(in: .whitespaces)
                return text.isEmpty ? nil : (true, text)
            }
        }
        return nil
    }
}
