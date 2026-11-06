// SPDX-License-Identifier: MIT
import AppKit
import Foundation

/// A copied RTF or RTFD document written as GitHub-Flavored Markdown: bold, italic, strikethrough, links, code in a
/// fixed-width font, lists (nested, bulleted or numbered) and tables. AppKit's rich-text import is not thread-safe,
/// so this runs on the main actor; RTF and RTFD import loads nothing from the network (the HTML flavour is read by
/// `HTMLMarkdown`, never by AppKit). Nil when the document held nothing to write as Markdown, and past a bound.
@MainActor
public enum RTFMarkdown {
    /// AppKit reads RTF at about 0.6 ms per KB on the main actor, and the menu asks when it opens (measured, ADR 0033),
    /// so this is much smaller than the HTML bound.
    public static let maxInputBytes = 32_000
    public static let maxOutputBytes = 5_000_000
    static let maxColumns = 200
    static let maxTableCells = 100_000

    public static func convert(_ data: Data, isRTFD: Bool = false) -> String? {
        guard data.count <= maxInputBytes,
              let attributed = try? NSAttributedString(
                  data: data,
                  options: [.documentType: isRTFD ? NSAttributedString.DocumentType.rtfd : .rtf],
                  documentAttributes: nil
              ) else { return nil }
        return markdown(from: attributed)
    }

    static func markdown(from attributed: NSAttributedString) -> String? {
        var converter = Converter(attributed: attributed)
        guard let text = converter.run(), converter.structure > 0, text.utf8.count <= maxOutputBytes else { return nil }
        return text
    }

    private struct RunKey: Equatable {
        var bold = false
        var italic = false
        var strike = false
        var mono = false
        var link: String?
    }

    private struct TableCell {
        let row: Int
        let column: Int
        let rowSpan: Int
        let columnSpan: Int
        var lines: [String] = []
    }

    @MainActor
    private struct Converter {
        let attributed: NSAttributedString
        var structure = 0
        var blocks: [String] = []
        var listLines: [String] = []
        var counters: [Int] = []
        var markerWidths: [Int] = []
        var table: NSTextTable?
        var cells: [TableCell] = []
        var failed = false

        init(attributed: NSAttributedString) {
            self.attributed = attributed
        }

        mutating func run() -> String? {
            let string = attributed.string as NSString
            var location = 0
            while location < string.length {
                let range = string.paragraphRange(for: NSRange(location: location, length: 0))
                location = NSMaxRange(range)
                let style = attributed.attribute(.paragraphStyle, at: range.location, effectiveRange: nil)
                    as? NSParagraphStyle
                let cell = style?.textBlocks.last as? NSTextTableBlock
                if cell?.table !== table { flushTable() }
                let text = inline(in: range, inCell: cell != nil)
                if let cell {
                    addToCell(cell, text)
                } else if let lists = style?.textLists, !lists.isEmpty {
                    addListItem(lists, text)
                } else {
                    let paragraph = MarkdownText.paragraph(text, cellBreak: false)
                    if !paragraph.isEmpty {
                        flushList()
                        blocks.append(paragraph)
                    }
                }
                if failed { return nil }
            }
            flushTable()
            flushList()
            let text = blocks.joined(separator: "\n\n")
            return text.isEmpty ? nil : text
        }

        // MARK: Lists

        private mutating func addListItem(_ lists: [NSTextList], _ text: String) {
            guard !MarkdownText.tidy(text).isEmpty else { return }
            let depth = lists.count
            if counters.count > depth {
                counters.removeSubrange(depth...)
                markerWidths.removeSubrange(depth...)
            }
            while counters.count < depth {
                counters.append(0)
                markerWidths.append(2)
            }
            counters[depth - 1] += 1
            let list = lists[depth - 1]
            let marker = Self.isOrdered(list) ? "\(list.startingItemNumber + counters[depth - 1] - 1). " : "- "
            markerWidths[depth - 1] = marker.count
            let indent = String(repeating: " ", count: markerWidths.dropLast().reduce(0, +))
            let continuation = "\n" + indent + String(repeating: " ", count: marker.count)
            listLines.append(indent + marker + MarkdownText.paragraph(text, cellBreak: false)
                .replacingOccurrences(of: "\n", with: continuation))
            structure += 1
        }

        private mutating func flushList() {
            if !listLines.isEmpty { blocks.append(listLines.joined(separator: "\n")) }
            listLines = []
            counters = []
            markerWidths = []
        }

        private static func isOrdered(_ list: NSTextList) -> Bool {
            let format = list.markerFormat.rawValue
            return ["decimal", "alpha", "roman", "octal", "hexadecimal", "upper", "lower"]
                .contains { format.contains($0) }
        }

        // MARK: Tables

        private mutating func addToCell(_ block: NSTextTableBlock, _ text: String) {
            flushList()
            if table == nil { table = block.table }
            let line = MarkdownText.paragraph(text, cellBreak: true)
            if let index = cells
                .firstIndex(where: { $0.row == block.startingRow && $0.column == block.startingColumn })
            {
                if !line.isEmpty { cells[index].lines.append(line) }
            } else {
                cells.append(TableCell(
                    row: block.startingRow, column: block.startingColumn, rowSpan: max(1, block.rowSpan),
                    columnSpan: max(1, block.columnSpan), lines: line.isEmpty ? [] : [line]
                ))
            }
            if cells.count > RTFMarkdown.maxTableCells { failed = true }
        }

        private mutating func flushTable() {
            defer {
                table = nil
                cells = []
            }
            guard !cells.isEmpty else { return }
            let rowCount = cells.map { $0.row + $0.rowSpan }.max() ?? 0
            let columnCount = cells.map { $0.column + $0.columnSpan }.max() ?? 0
            guard columnCount <= RTFMarkdown.maxColumns, rowCount * columnCount <= RTFMarkdown.maxTableCells else {
                failed = true
                return
            }
            if rowCount == 1, columnCount == 1 {
                let text = cells[0].lines.joined(separator: "\n")
                if !text.isEmpty { blocks.append(text.replacingOccurrences(of: "<br>", with: "\n")) }
                return
            }
            var grid = Array(repeating: Array(repeating: "", count: columnCount), count: rowCount)
            for cell in cells where cell.row < rowCount && cell.column < columnCount {
                grid[cell.row][cell.column] = cell.lines.joined(separator: "<br>")
            }
            structure += 1
            blocks.append(MarkdownText.table(grid))
        }

        // MARK: Inline

        private mutating func inline(in range: NSRange, inCell: Bool) -> String {
            var segments: [(key: RunKey, text: String)] = []
            attributed.enumerateAttributes(in: range, options: []) { attributes, runRange, _ in
                let raw = (attributed.string as NSString).substring(with: runRange)
                    .replacingOccurrences(of: "\u{FFFC}", with: "")
                    .replacingOccurrences(of: "\u{2028}", with: "\n")
                    .replacingOccurrences(of: "\u{0B}", with: "\n")
                guard !raw.isEmpty else { return }
                let key = Self.key(of: attributes)
                if let last = segments.last, last.key == key {
                    segments[segments.count - 1].text += raw
                } else {
                    segments.append((key, raw))
                }
            }
            var out = ""
            for segment in segments {
                out += render(segment.text, segment.key, inCell: inCell)
            }
            return out
        }

        private mutating func render(_ raw: String, _ key: RunKey, inCell: Bool) -> String {
            let withoutEnd = raw.hasSuffix("\n") ? String(raw.dropLast()) : raw
            guard !withoutEnd.isEmpty else { return "" }
            var text: String
            if key.mono, !withoutEnd.contains("\n") {
                text = MarkdownText.codeSpan(withoutEnd)
                if !text.isEmpty { structure += 1 }
            } else {
                text = withoutEnd.split(separator: "\n", omittingEmptySubsequences: false)
                    .map { MarkdownText.escape(MarkdownText.collapseWhitespace(String($0)), inTableCell: inCell) }
                    .joined(separator: String(MarkdownText.lineBreak))
            }
            for (enabled, marker) in [(key.italic, "*"), (key.bold, "**"), (key.strike, "~~")] where enabled {
                let wrapped = MarkdownText.wrap(text, with: marker)
                if wrapped != text { structure += 1 }
                text = wrapped
            }
            if let link = key.link, let destination = MarkdownText.linkDestination(link) {
                let core = MarkdownText.tidy(text)
                if !core.isEmpty {
                    structure += 1
                    let leading = text.prefix(while: { $0 == " " })
                    let trailing = text.reversed().prefix(while: { $0 == " " })
                    text = String(leading) + "[" + core + "](" + destination + ")" + String(trailing)
                }
            }
            return text
        }

        private static func key(of attributes: [NSAttributedString.Key: Any]) -> RunKey {
            var key = RunKey()
            if let font = attributes[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                key.bold = traits.contains(.bold)
                key.italic = traits.contains(.italic)
                key.mono = traits.contains(.monoSpace)
            }
            if let strike = attributes[.strikethroughStyle] as? Int { key.strike = strike != 0 }
            if let url = attributes[.link] as? URL {
                key.link = url.absoluteString
            } else if let text = attributes[.link] as? String {
                key.link = text
            }
            return key
        }
    }
}
