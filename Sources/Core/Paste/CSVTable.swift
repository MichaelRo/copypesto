// SPDX-License-Identifier: MIT
import Foundation

/// Comma or tab separated rows copied from a spreadsheet or a file, read as a table so Paste As can write them as a
/// JSON array of objects. It reads the UTF-8 bytes once: splitting by `Character` treats CRLF as one letter and is
/// several times slower. Every value stays the text of its cell (a zip code keeps its zero), and anything that is
/// not clearly a table is nil, so prose with commas never gets the entry.
public struct CSVTable: Equatable, Sendable {
    public static let maxInputBytes = 1_000_000
    public static let maxOutputBytes = 5_000_000
    public static let maxColumns = 200
    public static let maxHeaderCharacters = 40

    public let header: [String]
    public let rows: [[String]]

    private static let quote = UInt8(ascii: "\"")
    private static let space = UInt8(ascii: " ")
    private static let tab = UInt8(ascii: "\t")
    private static let comma = UInt8(ascii: ",")
    private static let lineFeed = UInt8(ascii: "\n")
    private static let carriageReturn = UInt8(ascii: "\r")

    /// `maxRows` stops reading after that many rows, header included: enough to say that a long table is one without
    /// reading it all when the menu opens.
    public static func parse(_ text: String, maxRows: Int = .max) -> CSVTable? {
        let bytes = Array(text.utf8)
        guard bytes.count <= maxInputBytes, bytes.count >= 3 else { return nil }
        var reader = Reader(bytes: bytes, maxRows: maxRows)
        guard let all = reader.readRows(), all.count >= 2 else { return nil }
        let header = all[0]
        guard isPlausibleHeader(header) else { return nil }
        if reader.delimiter == comma, endsLikeSentences(rows: all) { return nil }
        return CSVTable(header: header, rows: Array(all.dropFirst()))
    }

    public func jsonText(maxBytes: Int = CSVTable.maxOutputBytes) -> String? {
        let keys = header.map(Self.jsonString)
        var out: [UInt8] = []
        out.reserveCapacity(min(maxBytes, rows.count * header.count * 24 + 16))
        out.append(contentsOf: "[\n".utf8)
        for (rowIndex, row) in rows.enumerated() {
            out.append(contentsOf: "  {\n".utf8)
            for column in keys.indices {
                out.append(contentsOf: "    ".utf8)
                out.append(contentsOf: keys[column])
                out.append(contentsOf: ": ".utf8)
                out.append(contentsOf: Self.jsonString(row[column]))
                out.append(contentsOf: (column == keys.count - 1 ? "\n" : ",\n").utf8)
            }
            out.append(contentsOf: (rowIndex == rows.count - 1 ? "  }\n" : "  },\n").utf8)
            if out.count > maxBytes { return nil }
        }
        out.append(UInt8(ascii: "]"))
        return out.count > maxBytes ? nil : String(validating: out, as: UTF8.self) ?? ""
    }

    private static func isPlausibleHeader(_ header: [String]) -> Bool {
        guard header.count >= 2, header.count <= maxColumns else { return false }
        var seen = Set<String>()
        for name in header {
            guard !name.isEmpty, name.count <= maxHeaderCharacters, seen.insert(name).inserted else { return false }
            if let last = name.last, ".?!:;".contains(last) { return false }
        }
        return true
    }

    /// Every line of "Well, yes." and "Wait, what?" has the same number of commas; a table's last column does not
    /// end every row with a full stop.
    private static func endsLikeSentences(rows: [[String]]) -> Bool {
        rows.allSatisfy { row in
            guard let last = row.last?.last else { return false }
            return ".?!".contains(last)
        }
    }

    private static func jsonString(_ text: String) -> [UInt8] {
        var out: [UInt8] = [quote]
        out.reserveCapacity(text.utf8.count + 2)
        let hex = Array("0123456789abcdef".utf8)
        let backslash = UInt8(ascii: "\\")
        for byte in text.utf8 {
            switch byte {
            case quote: out.append(contentsOf: [backslash, quote])
            case backslash: out.append(contentsOf: [backslash, backslash])
            case lineFeed: out.append(contentsOf: [backslash, UInt8(ascii: "n")])
            case carriageReturn: out.append(contentsOf: [backslash, UInt8(ascii: "r")])
            case tab: out.append(contentsOf: [backslash, UInt8(ascii: "t")])
            case 0..<0x20:
                out.append(contentsOf: Array("\\u00".utf8) + [hex[Int(byte >> 4)], hex[Int(byte & 0xF)]])
            default: out.append(byte)
            }
        }
        out.append(quote)
        return out
    }

    private struct Reader {
        let bytes: [UInt8]
        let maxRows: Int
        var index = 0
        var delimiter = CSVTable.comma

        init(bytes: [UInt8], maxRows: Int) {
            self.bytes = bytes
            self.maxRows = maxRows
            if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { index = 3 }
            var probe = index
            while probe < bytes.count, bytes[probe] != CSVTable.lineFeed, bytes[probe] != CSVTable.carriageReturn {
                if bytes[probe] == CSVTable.tab {
                    delimiter = CSVTable.tab
                    break
                }
                probe += 1
            }
        }

        /// Nil when the text breaks a rule of a table (a quote left open, text after a closing quote, a row of another
        /// width, too many columns).
        mutating func readRows() -> [[String]]? {
            var rows: [[String]] = []
            while index < bytes.count, rows.count < maxRows {
                guard let row = readRow() else { return nil }
                if row.isBlank { continue }
                if let width = rows.first?.count, row.cells.count != width { return nil }
                if row.cells.count > CSVTable.maxColumns { return nil }
                rows.append(row.cells)
            }
            return rows
        }

        private mutating func readRow() -> (cells: [String], isBlank: Bool)? {
            var cells: [String] = []
            var sawStructure = false
            while true {
                guard let cell = readCell() else { return nil }
                cells.append(cell.text)
                if cell.wasQuoted { sawStructure = true }
                guard index < bytes.count else { break }
                let byte = bytes[index]
                if byte == delimiter {
                    index += 1
                    sawStructure = true
                    continue
                }
                let isCRLF = byte == CSVTable.carriageReturn && index + 1 < bytes.count
                    && bytes[index + 1] == CSVTable.lineFeed
                index += isCRLF ? 2 : 1
                break
            }
            return (cells, cells.count == 1 && cells[0].isEmpty && !sawStructure)
        }

        private mutating func readCell() -> (text: String, wasQuoted: Bool)? {
            var start = index
            while start < bytes.count, bytes[start] == CSVTable.space {
                start += 1
            }
            if start < bytes.count, bytes[start] == CSVTable.quote {
                return readQuotedCell(openingQuoteAt: start)
            }
            var end = start
            while end < bytes.count, bytes[end] != delimiter, bytes[end] != CSVTable.lineFeed,
                  bytes[end] != CSVTable.carriageReturn
            {
                end += 1
            }
            index = end
            var trimmed = end
            while trimmed > start, bytes[trimmed - 1] == CSVTable.space {
                trimmed -= 1
            }
            return (String(validating: bytes[start..<trimmed], as: UTF8.self) ?? "", false)
        }

        private mutating func readQuotedCell(openingQuoteAt start: Int) -> (text: String, wasQuoted: Bool)? {
            index = start + 1
            var cell: [UInt8] = []
            var closed = false
            while index < bytes.count {
                let byte = bytes[index]
                if byte == CSVTable.quote {
                    if index + 1 < bytes.count, bytes[index + 1] == CSVTable.quote {
                        cell.append(CSVTable.quote)
                        index += 2
                        continue
                    }
                    closed = true
                    index += 1
                    break
                }
                cell.append(byte)
                index += 1
            }
            guard closed else { return nil }
            while index < bytes.count, bytes[index] == CSVTable.space {
                index += 1
            }
            if index < bytes.count {
                let next = bytes[index]
                guard next == delimiter || next == CSVTable.lineFeed || next == CSVTable.carriageReturn else {
                    return nil
                }
            }
            return (String(validating: cell, as: UTF8.self) ?? "", true)
        }
    }
}
