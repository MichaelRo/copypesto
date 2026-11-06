// SPDX-License-Identifier: MIT
import Foundation

final class HTMLElement {
    let name: String
    let attributes: [String: String]
    var children: [HTMLNode] = []
    /// Set when a block element (paragraph, list, table, ...) was opened anywhere inside, so that an inline wrapper
    /// such as a link around a `div` is read as a container.
    var hasBlock = false

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }
}

enum HTMLNode {
    case text(String)
    case element(HTMLElement)
}

/// A forgiving tree of a copied HTML fragment, read without a browser engine: nothing the markup names is ever
/// requested. One pass over the bytes. Markup nested deeper than `maxDepth` or with more than `maxNodes` nodes is
/// refused, so hostile input costs time in proportion to its size and cannot overflow the stack of the code that
/// walks the tree.
enum HTMLTree {
    static let maxDepth = 96
    static let maxNodes = 150_000
    static let rootName = "#root"

    private static let dropped: Set<String> = [
        "script", "style", "head", "title", "template", "noscript", "svg", "iframe", "object", "embed", "select",
        "textarea", "button", "canvas", "audio", "video"
    ]
    private static let void: Set<String> = [
        "br", "hr", "img", "input", "meta", "link", "col", "wbr", "area", "base", "source", "track", "param"
    ]
    private static let blocks: Set<String> = [
        "p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "table", "tr", "td", "th", "thead", "tbody",
        "tfoot", "pre", "blockquote", "hr", "section", "article", "header", "footer", "nav", "main", "aside", "form",
        "fieldset", "figure", "figcaption", "dl", "dt", "dd", "address", "details", "summary", "center"
    ]

    static func parse(_ data: Data) -> HTMLElement? {
        let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        var builder = Builder(bytes: Array(html.utf8))
        return builder.run() ? builder.root : nil
    }

    private struct Builder {
        let bytes: [UInt8]
        let root = HTMLElement(name: HTMLTree.rootName, attributes: [:])
        var stack: [HTMLElement] = []
        var index = 0
        var text: [UInt8] = []
        var nodes = 0

        init(bytes: [UInt8]) {
            self.bytes = bytes
            stack = [root]
        }

        mutating func run() -> Bool {
            while index < bytes.count {
                if bytes[index] != UInt8(ascii: "<") {
                    text.append(bytes[index])
                    index += 1
                    continue
                }
                guard readMarkup() else { break }
                if nodes > HTMLTree.maxNodes || stack.count > HTMLTree.maxDepth { return false }
            }
            flushText()
            return nodes <= HTMLTree.maxNodes
        }

        /// False when the rest of the input is unusable (an unterminated tag or comment).
        private mutating func readMarkup() -> Bool {
            if matches("<!--", at: index) {
                guard let end = find("-->", from: index + 4) else { return false }
                flushText()
                index = end + 3
                return true
            }
            let next = index + 1 < bytes.count ? bytes[index + 1] : 0
            if next == UInt8(ascii: "!") || next == UInt8(ascii: "?") {
                guard let end = endOfTag(from: index + 2) else { return false }
                flushText()
                index = end + 1
                return true
            }
            var cursor = index + 1
            let closing = next == UInt8(ascii: "/")
            if closing { cursor += 1 }
            let nameStart = cursor
            while cursor < bytes.count, isNameByte(bytes[cursor]) {
                cursor += 1
            }
            guard cursor > nameStart else {
                text.append(bytes[index]) // "a < b" is text
                index += 1
                return true
            }
            let name = (String(validating: bytes[nameStart..<cursor], as: UTF8.self) ?? "").lowercased()
            guard let tagEnd = endOfTag(from: cursor) else { return false }
            flushText()
            let attributeBytes = bytes[cursor..<tagEnd]
            index = tagEnd + 1
            if closing {
                close(name)
            } else if HTMLTree.dropped.contains(name) {
                if bytes[tagEnd - 1] != UInt8(ascii: "/") {
                    guard let after = findClosing(name, from: index) else { return false }
                    index = after
                }
            } else {
                open(name, attributes: Self.attributes(in: attributeBytes))
            }
            return true
        }

        private mutating func open(_ name: String, attributes: [String: String]) {
            closeImpliedBy(name)
            let element = HTMLElement(name: name, attributes: attributes)
            nodes += 1
            stack[stack.count - 1].children.append(.element(element))
            if HTMLTree.blocks.contains(name) {
                for ancestor in stack.reversed() {
                    if ancestor.hasBlock { break }
                    ancestor.hasBlock = true
                }
            }
            if !HTMLTree.void.contains(name) { stack.append(element) }
        }

        private mutating func close(_ name: String) {
            guard let position = stack.lastIndex(where: { $0.name == name }), position > 0 else { return }
            stack.removeSubrange(position...)
        }

        /// The end tags HTML leaves out: a new `li` ends the open one, a `td` ends the open cell, a `p` ends the
        /// open paragraph. The search stops at the first element that starts a scope of its own.
        private mutating func closeImpliedBy(_ name: String) {
            let closes: Set<String>
            let boundary: Set<String>
            switch name {
            case "li": (closes, boundary) = (["li"], ["ul", "ol", "table"])
            case "td", "th": (closes, boundary) = (["td", "th"], ["tr", "table"])
            case "tr": (closes, boundary) = (["tr", "td", "th"], ["table"])
            case "thead", "tbody", "tfoot": (closes, boundary) = (
                    ["thead", "tbody", "tfoot", "tr", "td", "th"],
                    ["table"]
                )
            case "dt", "dd": (closes, boundary) = (["dt", "dd"], ["dl", "table"])
            case "p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "table", "pre", "blockquote", "hr":
                (closes, boundary) = (["p"], ["td", "th", "li", "table", "blockquote", "div", "body", "ul", "ol"])
            default: return
            }
            for position in stride(from: stack.count - 1, to: 0, by: -1) {
                let candidate = stack[position].name
                if closes.contains(candidate) {
                    stack.removeSubrange(position...)
                    return
                }
                if boundary.contains(candidate) { return }
            }
        }

        private mutating func flushText() {
            guard !text.isEmpty else { return }
            let decoded = HTMLEntities.decode(String(validating: text, as: UTF8.self) ?? "")
            text.removeAll(keepingCapacity: true)
            nodes += 1
            stack[stack.count - 1].children.append(.text(decoded))
        }

        private static func attributes(in bytes: ArraySlice<UInt8>) -> [String: String] {
            var result: [String: String] = [:]
            var cursor = bytes.startIndex
            func skipSpaces() {
                while cursor < bytes.endIndex, isSpace(bytes[cursor]) || bytes[cursor] == UInt8(ascii: "/") {
                    cursor += 1
                }
            }
            while cursor < bytes.endIndex {
                skipSpaces()
                let nameStart = cursor
                while cursor < bytes.endIndex, !isSpace(bytes[cursor]), bytes[cursor] != UInt8(ascii: "="),
                      bytes[cursor] != UInt8(ascii: "/")
                {
                    cursor += 1
                }
                guard cursor > nameStart else { break }
                let name = (String(validating: bytes[nameStart..<cursor], as: UTF8.self) ?? "").lowercased()
                while cursor < bytes.endIndex, isSpace(bytes[cursor]) {
                    cursor += 1
                }
                var value = ""
                if cursor < bytes.endIndex, bytes[cursor] == UInt8(ascii: "=") {
                    cursor += 1
                    while cursor < bytes.endIndex, isSpace(bytes[cursor]) {
                        cursor += 1
                    }
                    if cursor < bytes.endIndex,
                       bytes[cursor] == UInt8(ascii: "\"") || bytes[cursor] == UInt8(ascii: "'")
                    {
                        let quote = bytes[cursor]
                        cursor += 1
                        let valueStart = cursor
                        while cursor < bytes.endIndex, bytes[cursor] != quote {
                            cursor += 1
                        }
                        value = String(validating: bytes[valueStart..<cursor], as: UTF8.self) ?? ""
                        if cursor < bytes.endIndex { cursor += 1 }
                    } else {
                        let valueStart = cursor
                        while cursor < bytes.endIndex, !isSpace(bytes[cursor]) {
                            cursor += 1
                        }
                        value = String(validating: bytes[valueStart..<cursor], as: UTF8.self) ?? ""
                    }
                }
                if result[name] == nil, ["href", "src", "alt", "style", "colspan", "rowspan", "class", "start", "type"]
                    .contains(name)
                {
                    result[name] = HTMLEntities.decode(value)
                }
            }
            return result
        }

        private static func isSpace(_ byte: UInt8) -> Bool {
            byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r")
                || byte == UInt8(ascii: "\t") || byte == 0x0C
        }

        /// The index of the `>` that ends the tag, skipping any inside a quoted attribute value.
        private func endOfTag(from start: Int) -> Int? {
            var quote: UInt8?
            var cursor = start
            while cursor < bytes.count {
                let byte = bytes[cursor]
                if let open = quote {
                    if byte == open { quote = nil }
                } else if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
                    quote = byte
                } else if byte == UInt8(ascii: ">") {
                    return cursor
                }
                cursor += 1
            }
            return nil
        }

        private func findClosing(_ name: String, from start: Int) -> Int? {
            let pattern = Array("</\(name)".utf8)
            var cursor = start
            while cursor + pattern.count <= bytes.count {
                if bytes[cursor] == UInt8(ascii: "<"), matchesIgnoringCase(pattern, at: cursor),
                   let end = endOfTag(from: cursor + pattern.count)
                {
                    return end + 1
                }
                cursor += 1
            }
            return nil
        }

        private func matches(_ literal: String, at position: Int) -> Bool {
            let pattern = Array(literal.utf8)
            guard position + pattern.count <= bytes.count else { return false }
            return pattern.indices.allSatisfy { bytes[position + $0] == pattern[$0] }
        }

        private func matchesIgnoringCase(_ pattern: [UInt8], at position: Int) -> Bool {
            pattern.indices.allSatisfy { lowercased(bytes[position + $0]) == pattern[$0] }
        }

        private func find(_ literal: String, from start: Int) -> Int? {
            var cursor = start
            while cursor + literal.utf8.count <= bytes.count {
                if matches(literal, at: cursor) { return cursor }
                cursor += 1
            }
            return nil
        }

        private func lowercased(_ byte: UInt8) -> UInt8 {
            (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) ? byte + 32 : byte
        }

        private func isNameByte(_ byte: UInt8) -> Bool {
            (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
                || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
                || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
                || byte == UInt8(ascii: ":") || byte == UInt8(ascii: "-") || byte == UInt8(ascii: "_")
        }
    }
}
