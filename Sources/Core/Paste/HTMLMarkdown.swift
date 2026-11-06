// SPDX-License-Identifier: MIT
import Foundation

/// A copied HTML fragment written as GitHub-Flavored Markdown: headings, paragraphs, bold, italic, strikethrough,
/// links, inline code and code blocks, quotes, rules, lists (nested), pictures and tables. It reads the markup
/// itself and requests nothing it names (`HTMLTree`). Nil when the markup held nothing to write as Markdown, so a
/// styled `<span>` from any web page does not get the entry, and when it is past a bound.
public enum HTMLMarkdown {
    /// Converted at about 0.1 ms per KB in a release build (measured, ADR 0033), asked when the menu opens.
    public static let maxInputBytes = 128_000
    public static let maxOutputBytes = 5_000_000
    static let maxTableCells = 100_000
    static let maxColumns = 200

    public static func convert(_ data: Data) -> String? {
        guard data.count <= maxInputBytes, let root = HTMLTree.parse(data) else { return nil }
        var converter = Converter()
        let blocks = converter.blocks(root.children, Context())
        guard !converter.failed, converter.structure > 0 else { return nil }
        let text = blocks.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n")
        guard !text.isEmpty, text.utf8.count <= maxOutputBytes else { return nil }
        return text
    }

    private struct Style {
        var bold = false
        var italic = false
        var strike = false
    }

    private struct Context {
        var style = Style()
        var inCell = false
    }

    private struct TableCell {
        let element: HTMLElement
        let columns: Int
        let rows: Int
    }

    private struct Block {
        var text: String
        var isList = false
    }

    private struct Converter {
        var structure = 0
        var cellCount = 0
        var failed = false

        // MARK: Blocks

        mutating func blocks(_ nodes: [HTMLNode], _ context: Context) -> [Block] {
            var out: [Block] = []
            var run: [HTMLNode] = []
            func flush(_ converter: inout Converter) {
                guard !run.isEmpty else { return }
                let text = MarkdownText.paragraph(converter.inline(run, context), cellBreak: context.inCell)
                run.removeAll()
                if !text.isEmpty { out.append(Block(text: text)) }
            }
            for node in nodes {
                guard case let .element(element) = node else {
                    run.append(node)
                    continue
                }
                switch element.name {
                case "p", "div", "section", "article", "header", "footer", "nav", "main", "aside", "form", "fieldset",
                     "figure", "figcaption", "center", "dl", "dt", "dd", "address", "details", "summary", "body",
                     "html",
                     "tbody", "thead", "tfoot", "tr", "td", "th", "li":
                    flush(&self)
                    out += blocks(element.children, context)
                case "h1", "h2", "h3", "h4", "h5", "h6":
                    flush(&self)
                    out += heading(element, context)
                case "ul", "ol":
                    flush(&self)
                    out += list(element, ordered: element.name == "ol", context)
                case "table":
                    flush(&self)
                    out += table(element, context)
                case "pre":
                    flush(&self)
                    out += preformatted(element, context)
                case "blockquote":
                    flush(&self)
                    out += blockquote(element, context)
                case "hr":
                    flush(&self)
                    if !context.inCell {
                        structure += 1
                        out.append(Block(text: "---"))
                    }
                default:
                    if element.hasBlock {
                        flush(&self)
                        out += blocks(element.children, context)
                    } else {
                        run.append(node)
                    }
                }
            }
            flush(&self)
            return out
        }

        private mutating func heading(_ element: HTMLElement, _ context: Context) -> [Block] {
            var inner = context
            inner.style.bold = true
            let text = MarkdownText.paragraph(inline(element.children, inner), cellBreak: true)
                .replacingOccurrences(of: "<br>", with: " ")
            guard !text.isEmpty else { return [] }
            if context.inCell { return [Block(text: text)] }
            structure += 1
            let level = Int(element.name.dropFirst()) ?? 1
            return [Block(text: String(repeating: "#", count: level) + " " + text)]
        }

        private mutating func blockquote(_ element: HTMLElement, _ context: Context) -> [Block] {
            let inner = blocks(element.children, context)
            guard !inner.isEmpty else { return [] }
            if context.inCell { return inner }
            structure += 1
            let text = inner.map(\.text).joined(separator: "\n\n")
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.isEmpty ? ">" : "> " + $0 }
                .joined(separator: "\n")
            return [Block(text: text)]
        }

        private mutating func preformatted(_ element: HTMLElement, _ context: Context) -> [Block] {
            var raw = rawText(element)
            if raw.hasPrefix("\n") { raw.removeFirst() }
            while raw.hasSuffix("\n") {
                raw.removeLast()
            }
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
            if context.inCell {
                return [Block(text: MarkdownText.escape(raw, inTableCell: true).replacingOccurrences(
                    of: "\n",
                    with: "<br>"
                ))]
            }
            structure += 1
            return [Block(text: MarkdownText.fencedCode(raw, language: language(of: element)))]
        }

        private func language(of element: HTMLElement) -> String? {
            for node in element.children {
                guard case let .element(child) = node, child.name == "code" else { continue }
                let classes = (child.attributes["class"] ?? "").split(separator: " ")
                for name in classes {
                    for prefix in ["language-", "lang-"] where name.hasPrefix(prefix) {
                        let language = String(name.dropFirst(prefix.count))
                        if !language.isEmpty,
                           language.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+#-_".contains($0)) })
                        {
                            return language
                        }
                    }
                }
            }
            return nil
        }

        // MARK: Lists

        private mutating func list(_ element: HTMLElement, ordered: Bool, _ context: Context) -> [Block] {
            var items: [String] = []
            var number = max(1, min(Int(element.attributes["start"] ?? "") ?? 1, 999_999))
            for node in element.children {
                guard case let .element(child) = node else { continue }
                if child.name == "li" {
                    let marker = context.inCell ? "\u{2022} " : (ordered ? "\(number). " : "- ")
                    let inner = blocks(child.children, context)
                    guard !inner.isEmpty else { continue }
                    number += 1
                    items.append(item(inner, marker: marker, inCell: context.inCell))
                } else if child.name == "ul" || child.name == "ol", !items.isEmpty {
                    let nested = list(child, ordered: child.name == "ol", context)
                    if let text = nested.first?.text {
                        items[items.count - 1] += context.inCell ? "<br>" + text : "\n" + indent(text, by: 2)
                    }
                }
            }
            guard !items.isEmpty else { return [] }
            if context.inCell { return [Block(text: items.joined(separator: "<br>"), isList: true)] }
            structure += 1
            return [Block(text: items.joined(separator: "\n"), isList: true)]
        }

        private func item(_ inner: [Block], marker: String, inCell: Bool) -> String {
            var text = inner[0].text
            for block in inner.dropFirst() {
                text += (inCell ? "<br>" : (block.isList ? "\n" : "\n\n")) + block.text
            }
            if inCell { return marker + text }
            return marker + indent(text, by: marker.count, skippingFirst: true)
        }

        private func indent(_ text: String, by width: Int, skippingFirst: Bool = false) -> String {
            let pad = String(repeating: " ", count: width)
            return text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                .map { offset, line in line.isEmpty || (skippingFirst && offset == 0) ? String(line) : pad + line }
                .joined(separator: "\n")
        }

        // MARK: Tables

        private mutating func table(_ element: HTMLElement, _ context: Context) -> [Block] {
            var rows: [[TableCell]] = []
            collectRows(element, into: &rows)
            guard !rows.isEmpty else { return [] }
            if rows.count == 1, rows[0].count == 1 { return blocks(rows[0][0].element.children, context) }
            var inner = context
            inner.inCell = true
            var grid: [[String]] = []
            var pending: [Int] = []
            for row in rows {
                var line: [String] = []
                func fillPending() {
                    while line.count < pending.count, pending[line.count] > 0 {
                        pending[line.count] -= 1
                        line.append("")
                    }
                }
                for cell in row {
                    fillPending()
                    let start = line.count
                    line.append(cellText(cell.element, inner))
                    line += Array(repeating: "", count: cell.columns - 1)
                    while pending.count < line.count {
                        pending.append(0)
                    }
                    for column in start..<line.count {
                        pending[column] = cell.rows - 1
                    }
                    cellCount += cell.columns
                    if line.count > HTMLMarkdown.maxColumns || cellCount > HTMLMarkdown.maxTableCells {
                        failed = true
                        return []
                    }
                }
                fillPending()
                guard line.count <= HTMLMarkdown.maxColumns, cellCount <= HTMLMarkdown.maxTableCells else {
                    failed = true
                    return []
                }
                grid.append(line)
            }
            if context.inCell {
                return [Block(text: grid.map { $0.filter { !$0.isEmpty }.joined(separator: ", ") }
                        .filter { !$0.isEmpty }.joined(separator: "<br>"))]
            }
            structure += 1
            return [Block(text: MarkdownText.table(grid))]
        }

        private func collectRows(_ element: HTMLElement, into rows: inout [[TableCell]]) {
            for node in element.children {
                guard case let .element(child) = node else { continue }
                switch child.name {
                case "tr":
                    let cells = child.children.compactMap { node -> TableCell? in
                        guard case let .element(cell) = node, cell.name == "td" || cell.name == "th" else { return nil }
                        return TableCell(
                            element: cell,
                            columns: span(cell.attributes["colspan"]),
                            rows: span(cell.attributes["rowspan"])
                        )
                    }
                    if !cells.isEmpty { rows.append(cells) }
                case "thead", "tbody", "tfoot":
                    collectRows(child, into: &rows)
                default:
                    break
                }
            }
        }

        private func span(_ value: String?) -> Int {
            max(1, min(Int((value ?? "").trimmingCharacters(in: .whitespaces)) ?? 1, 100))
        }

        private mutating func cellText(_ cell: HTMLElement, _ context: Context) -> String {
            blocks(cell.children, context).map(\.text).filter { !$0.isEmpty }.joined(separator: "<br>")
                .replacingOccurrences(of: "\n", with: "<br>")
        }

        // MARK: Inline

        mutating func inline(_ nodes: [HTMLNode], _ context: Context) -> String {
            var out = ""
            for node in nodes {
                switch node {
                case let .text(text):
                    out += MarkdownText.escape(MarkdownText.collapseWhitespace(text), inTableCell: context.inCell)
                case let .element(element):
                    out += inlineElement(element, context)
                }
            }
            return out
        }

        private mutating func inlineElement(_ element: HTMLElement, _ context: Context) -> String {
            switch element.name {
            case "br": return String(MarkdownText.lineBreak)
            case "img": return image(element, context)
            case "a": return link(element, context)
            case "code", "kbd", "samp", "tt":
                let span = MarkdownText.codeSpan(rawText(element))
                if !span.isEmpty { structure += 1 }
                return context.inCell ? span.replacingOccurrences(of: "|", with: "\\|") : span
            default:
                return styled(element, context)
            }
        }

        private mutating func styled(_ element: HTMLElement, _ context: Context) -> String {
            let flags = StyleFlags(element)
            var inner = context
            var markers: [String] = []
            if flags.italic, !context.style.italic {
                inner.style.italic = true
                markers.append("*")
            }
            if flags.bold, !context.style.bold {
                inner.style.bold = true
                markers.append("**")
            }
            if flags.strike, !context.style.strike {
                inner.style.strike = true
                markers.append("~~")
            }
            var text = self.inline(element.children, inner)
            for marker in markers {
                let wrapped = MarkdownText.wrap(text, with: marker)
                if wrapped != text { structure += 1 }
                text = wrapped
            }
            return text
        }

        private mutating func link(_ element: HTMLElement, _ context: Context) -> String {
            let text = inline(element.children, context)
            guard let destination = MarkdownText.linkDestination(element.attributes["href"] ?? "") else { return text }
            let core = MarkdownText.tidy(text)
            guard !core.isEmpty else { return text }
            structure += 1
            let raw = rawText(element).trimmingCharacters(in: .whitespacesAndNewlines)
            let address = (element.attributes["href"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if raw == address, raw.lowercased().hasPrefix("http"), destination == address,
               !raw.contains(where: { $0 == "<" || $0 == ">" || $0 == " " })
            {
                return " <" + address + "> "
            }
            let leading = text.prefix(while: { $0 == " " || $0 == MarkdownText.lineBreak })
            let trailing = text.reversed().prefix(while: { $0 == " " || $0 == MarkdownText.lineBreak }).reversed()
            return String(leading) + "[" + core + "](" + destination + ")" + String(trailing)
        }

        private mutating func image(_ element: HTMLElement, _ context: Context) -> String {
            let alt = MarkdownText.escape(
                MarkdownText.collapseWhitespace(element.attributes["alt"] ?? ""), inTableCell: context.inCell
            ).trimmingCharacters(in: .whitespaces)
            guard let source = MarkdownText.linkDestination(element.attributes["src"] ?? "") else { return alt }
            structure += 1
            return "![" + alt + "](" + source + ")"
        }

        private func rawText(_ element: HTMLElement) -> String {
            var out = ""
            for node in element.children {
                switch node {
                case let .text(text): out += text
                case let .element(child):
                    if child.name == "br" { out += "\n" } else { out += rawText(child) }
                }
            }
            return out
        }
    }

    private struct StyleFlags {
        var bold = false
        var italic = false
        var strike = false

        init(_ element: HTMLElement) {
            switch element.name {
            case "b", "strong": bold = true
            case "i", "em", "cite", "dfn": italic = true
            case "s", "strike", "del": strike = true
            default: break
            }
            let style = (element.attributes["style"] ?? "").lowercased()
            guard !style.isEmpty else { return }
            if let weight = Self.value(of: "font-weight", in: style) {
                if ["normal", "lighter", "400", "300", "200", "100"].contains(weight) {
                    bold = false
                } else if weight == "bold" || weight == "bolder" || (Int(weight) ?? 0) >= 600 {
                    bold = true
                }
            }
            if let fontStyle = Self.value(of: "font-style", in: style) {
                if fontStyle == "italic" || fontStyle == "oblique" {
                    italic = true
                } else if fontStyle == "normal" {
                    italic = false
                }
            }
            if let decoration = Self.value(of: "text-decoration", in: style), decoration.contains("line-through") {
                strike = true
            }
        }

        private static func value(of property: String, in style: String) -> String? {
            for declaration in style.split(separator: ";") {
                let parts = declaration.split(separator: ":", maxSplits: 1)
                guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == property else { continue }
                return parts[1].trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "!important", with: "").trimmingCharacters(in: .whitespaces)
            }
            return nil
        }
    }
}
