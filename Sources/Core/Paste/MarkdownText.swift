// SPDX-License-Identifier: MIT
import Foundation

/// The pieces of GitHub-Flavored Markdown that the HTML and RTF converters share: what must be escaped in a run of
/// text, emphasis that keeps its spaces outside the markers, code spans, link destinations and a table.
enum MarkdownText {
    /// Stands for a line break inside a paragraph until the paragraph is finished (a backslash and a newline, or
    /// `<br>` in a table cell), so that the spaces around it can be cleaned up first.
    static let lineBreak: Character = "\u{2028}"

    static func collapseWhitespace(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        var pendingSpace = false
        for character in text {
            if character.isWhitespace {
                pendingSpace = true
                continue
            }
            if pendingSpace {
                out.append(" ")
                pendingSpace = false
            }
            out.append(character)
        }
        if pendingSpace { out.append(" ") }
        return out
    }

    static func escape(_ text: String, inTableCell: Bool = false) -> String {
        let characters = Array(text)
        var out = ""
        out.reserveCapacity(characters.count + 8)
        for (index, character) in characters.enumerated() {
            let previous = index > 0 ? characters[index - 1] : nil
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            switch character {
            case "\\", "`", "*", "[", "]":
                out.append("\\")
                out.append(character)
            case "_":
                let inWord = previous.map { $0.isLetter || $0.isNumber } == true
                    && next.map { $0.isLetter || $0.isNumber } == true
                if !inWord { out.append("\\") }
                out.append(character)
            case "<":
                if let next, next.isLetter || next == "/" || next == "!" || next == "?" { out.append("\\") }
                out.append(character)
            case "~":
                if previous == "~" || next == "~" { out.append("\\") }
                out.append(character)
            case "|":
                if inTableCell { out.append("\\") }
                out.append(character)
            default:
                out.append(character)
            }
        }
        return out
    }

    /// Spaces collapsed, none beside a line break, and none at either end.
    static func tidy(_ inline: String) -> String {
        var out: [Character] = []
        out.reserveCapacity(inline.utf8.count)
        for character in inline {
            if character == " " {
                if let last = out.last, last != " ", last != lineBreak { out.append(character) }
            } else if character == lineBreak {
                if out.last == " " { out.removeLast() }
                if out.last != lineBreak, !out.isEmpty { out.append(character) }
            } else {
                out.append(character)
            }
        }
        while let last = out.last, last == " " || last == lineBreak {
            out.removeLast()
        }
        return String(out)
    }

    static func paragraph(_ inline: String, cellBreak: Bool) -> String {
        let tidied = tidy(inline)
        guard !tidied.isEmpty else { return "" }
        if cellBreak { return tidied.replacingOccurrences(of: String(lineBreak), with: "<br>") }
        return protectLineStarts(tidied).replacingOccurrences(of: String(lineBreak), with: "\\\n")
    }

    /// A line that would turn into a heading, a quote, a list or a rule when it only happens to start that way.
    private static func protectLineStarts(_ text: String) -> String {
        text.split(separator: lineBreak, omittingEmptySubsequences: false)
            .map { protectLineStart(String($0)) }
            .joined(separator: String(lineBreak))
    }

    private static func protectLineStart(_ line: String) -> String {
        guard let first = line.first else { return line }
        let second = line.dropFirst().first
        switch first {
        case "#":
            let hashes = line.prefix(while: { $0 == "#" })
            let after = line.dropFirst(hashes.count).first
            if hashes.count <= 6, after == nil || after == " " { return "\\" + line }
        case ">":
            return "\\" + line
        case "-", "+":
            if second == nil || second == " " || (first == "-" && second == "-") { return "\\" + line }
        case "=":
            if line.allSatisfy({ $0 == "=" }) { return "\\" + line }
        default:
            let digits = line.prefix(while: { $0.isASCII && $0.isNumber })
            if !digits.isEmpty, digits.count <= 9 {
                let rest = line.dropFirst(digits.count)
                if let mark = rest.first, mark == "." || mark == ")",
                   rest.dropFirst().first == nil || rest.dropFirst().first == " "
                {
                    return String(digits) + "\\" + rest
                }
            }
        }
        return line
    }

    /// `**core**` with the spaces and line breaks at the ends of `inner` left outside, as Markdown needs. Text that
    /// is only spaces gets no marker.
    static func wrap(_ inner: String, with marker: String) -> String {
        let isEdge: (Character) -> Bool = { $0 == " " || $0 == lineBreak }
        let leading = inner.prefix(while: isEdge)
        let trailing = inner.reversed().prefix(while: isEdge).reversed()
        let core = inner.dropFirst(leading.count).dropLast(trailing.count)
        guard !core.isEmpty else { return inner }
        return String(leading) + marker + core + marker + String(trailing)
    }

    static func codeSpan(_ raw: String) -> String {
        let text = raw.replacingOccurrences(of: "\n", with: " ")
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return "" }
        var longest = 0
        var run = 0
        for character in text {
            run = character == "`" ? run + 1 : 0
            longest = max(longest, run)
        }
        let fence = String(repeating: "`", count: longest + 1)
        let pad = text.hasPrefix("`") || text.hasSuffix("`") ? " " : ""
        return fence + pad + text + pad + fence
    }

    /// The text of a block of code, fenced with more backticks than any line of it starts with.
    static func fencedCode(_ raw: String, language: String?) -> String {
        var longest = 2
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let ticks = line.drop(while: { $0 == " " }).prefix(while: { $0 == "`" }).count
            longest = max(longest, ticks)
        }
        let fence = String(repeating: "`", count: longest + 1)
        return fence + (language ?? "") + "\n" + raw + "\n" + fence
    }

    /// The address as it can stand in `(...)`, or nil unless it is a web address, a mail address or a relative one.
    /// Nothing else (`javascript:`, `data:`, `file:`) is ever written into a link.
    static func linkDestination(_ address: String, allowRelative: Bool = true) -> String? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 2000,
              !trimmed.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else { return nil }
        let lowered = trimmed.lowercased()
        let isAbsolute = lowered.hasPrefix("http://") || lowered.hasPrefix("https://") || lowered.hasPrefix("mailto:")
        if !isAbsolute {
            let firstDelimiter = lowered.firstIndex(where: { "/?#".contains($0) }) ?? lowered.endIndex
            guard allowRelative, !lowered[..<firstDelimiter].contains(":") else { return nil }
        }
        var out = ""
        for character in trimmed {
            switch character {
            case " ": out += "%20"
            case "(": out += "%28"
            case ")": out += "%29"
            case "<": out += "%3C"
            case ">": out += "%3E"
            case "\\": out += "%5C"
            default: out.append(character)
            }
        }
        return out
    }

    static func table(_ grid: [[String]]) -> String {
        let width = grid.map(\.count).max() ?? 0
        guard width > 0 else { return "" }
        let lines = grid.map { row -> String in
            let cells = row + Array(repeating: "", count: width - row.count)
            return "| " + cells.joined(separator: " | ") + " |"
        }
        let rule = "| " + Array(repeating: "---", count: width).joined(separator: " | ") + " |"
        return ([lines[0], rule] + lines.dropFirst()).joined(separator: "\n")
    }
}
