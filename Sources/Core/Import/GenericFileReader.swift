// SPDX-License-Identifier: MIT
import Foundation

/// Reads a CSV, JSON or text file of clips (ADR 0011: a copy, read-only, bounded, nothing imported until confirmed).
public enum GenericFileReader {
    public enum ReadError: Error, Equatable {
        case tooLarge
        case notRecognized
    }

    public static let maxBytes = 20_000_000
    /// A clip longer than this is left out and counted, as a copy over `ClipSizePolicy` is refused.
    public static let maxClipCharacters = 1_000_000
    public static let pinnedCollectionName = "Pinned from the imported file"

    public static func read(_ data: Data, fileExtension: String, maxBytes: Int = maxBytes) throws -> GenericFile {
        guard data.count <= maxBytes else { throw ReadError.tooLarge }
        guard let text = decode(data) else { throw ReadError.notRecognized }
        switch format(for: fileExtension.lowercased(), text: text) {
        case .json: return try json(text)
        case .csv: return csv(text, delimiter: fileExtension.lowercased() == "tsv" ? "\t" : nil)
        case .text: return GenericFile(format: .text, columns: [], rows: [], text: text)
        }
    }

    // MARK: Clips

    private struct Candidate {
        let text: String
        let date: Date?
        let pinned: Bool
    }

    public static func library(from file: GenericFile, mapping: GenericFileMapping, now: Date = .now)
    -> ClipboardAppLibrary {
        let candidates: [Candidate] = switch file.format {
        case .text:
            blocks(of: file.text, separator: mapping.separator).map { Candidate(text: $0, date: nil, pinned: false) }
        case .csv, .json:
            file.rows.map { row in
                func cell(_ column: Int?) -> String? {
                    guard let column, row.indices.contains(column) else { return nil }
                    return row[column]
                }
                return Candidate(
                    text: cell(mapping.textColumn) ?? "",
                    date: cell(mapping.dateColumn).flatMap(date(from:)),
                    pinned: cell(mapping.pinnedColumn).map(isTruthy) ?? false
                )
            }
        }
        var records: [PasteImportRecord] = []
        var skipped = 0
        let total = min(candidates.count, ClipboardAppLibraryReader.maxRecords)
        for (index, candidate) in candidates.prefix(total).enumerated() {
            let trimmed = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= maxClipCharacters else {
                skipped += 1
                continue
            }
            // Rows with no date keep the file's order, the later ones newer, the last one at the import time.
            let stamp = candidate.date ?? now.addingTimeInterval(-Double(total - 1 - index) * 0.001)
            records.append(PasteImportRecord(
                pinboard: candidate.pinned ? pinnedCollectionName : nil, title: nil, timestamp: min(stamp, now),
                sourceBundleID: nil,
                representations: [.init(
                    uti: "public.utf8-plain-text",
                    dataBase64: Data(trimmed.utf8).base64EncodedString()
                )]
            ))
        }
        return ClipboardAppLibrary(records: records, skipped: skipped)
    }

    // MARK: Decoding and format

    private static func decode(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(3))
        let text: String? = if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) {
            data.count.isMultiple(of: 2) ? String(data: data, encoding: .utf16) : nil
        } else if bytes == [0xEF, 0xBB, 0xBF] {
            String(data: data.dropFirst(3), encoding: .utf8)
        } else {
            String(data: data, encoding: .utf8)
        }
        guard let text, !text.unicodeScalars.contains("\u{0}") else { return nil }
        return text
    }

    private static func format(for fileExtension: String, text: String) -> GenericFile.Format {
        switch fileExtension {
        case "csv", "tsv": return .csv
        case "json": return .json
        case "txt", "text", "md": return .text
        default: break
        }
        let head = text.prefix(2000).trimmingCharacters(in: .whitespacesAndNewlines)
        if head.hasPrefix("[") || head.hasPrefix("{") { return .json }
        let lines = head.split(whereSeparator: \.isNewline).prefix(5).map(String.init)
        if lines.count >= 2 {
            for delimiter in [",", ";", "\t"] {
                let counts = Set(lines.map { $0.count(where: { String($0) == delimiter }) })
                if counts.count == 1, let count = counts.first, count > 0 { return .csv }
            }
        }
        return .text
    }

    // MARK: CSV

    private static func csv(_ text: String, delimiter forced: Character?) -> GenericFile {
        let bytes = Array(text.utf8)
        let delimiter = forced.flatMap(\.asciiValue) ?? detectDelimiter(bytes)
        let table = parseCSV(bytes, delimiter: delimiter, maxRows: ClipboardAppLibraryReader.maxRecords + 1)
        guard let header = table.first else { return GenericFile(format: .csv, columns: [], rows: [], text: "") }
        let width = header.count
        let rows = table.dropFirst().map { row -> [String] in
            if row.count == width { return row }
            return row.count > width ? Array(row.prefix(width)) : row + Array(repeating: "", count: width - row.count)
        }
        return GenericFile(format: .csv, columns: header, rows: Array(rows), text: "")
    }

    private static func detectDelimiter(_ bytes: [UInt8]) -> UInt8 {
        var counts: [UInt8: Int] = [UInt8(ascii: ","): 0, UInt8(ascii: ";"): 0, UInt8(ascii: "\t"): 0]
        var inQuotes = false
        for byte in bytes.prefix(4000) {
            if byte == UInt8(ascii: "\"") { inQuotes.toggle() }
            if !inQuotes, byte == 10 || byte == 13 { break }
            if !inQuotes, let count = counts[byte] { counts[byte] = count + 1 }
        }
        return counts.max { $0.value < $1.value }.flatMap { $0.value > 0 ? $0.key : nil } ?? UInt8(ascii: ",")
    }

    private static func parseCSV(_ bytes: [UInt8], delimiter: UInt8, maxRows: Int) -> [[String]] {
        var table: [[String]] = []
        var row: [String] = []
        var field: [UInt8] = []
        var inQuotes = false
        var fieldWasQuoted = false
        var index = 0
        func endField() {
            row.append(String(bytes: field, encoding: .utf8) ?? "")
            field.removeAll(keepingCapacity: true)
            fieldWasQuoted = false
        }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) { table.append(row) }
            row = []
        }
        while index < bytes.count, table.count < maxRows {
            let byte = bytes[index]
            if inQuotes {
                if byte == UInt8(ascii: "\"") {
                    if index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "\"") {
                        field.append(byte)
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(byte)
                }
            } else if byte == UInt8(ascii: "\""), field.isEmpty, !fieldWasQuoted {
                inQuotes = true
                fieldWasQuoted = true
            } else if byte == delimiter {
                endField()
            } else if byte == 13 {
                if index + 1 < bytes.count, bytes[index + 1] == 10 { index += 1 }
                endRow()
            } else if byte == 10 {
                endRow()
            } else {
                field.append(byte)
            }
            index += 1
        }
        if table.count < maxRows, !field.isEmpty || !row.isEmpty { endRow() }
        return table
    }

    // MARK: JSON

    private static func json(_ text: String) throws -> GenericFile {
        guard let value = try? JSONSerialization.jsonObject(with: Data(text.utf8)) else {
            throw ReadError.notRecognized
        }
        var list = value as? [Any]
        if list == nil, let object = value as? [String: Any] {
            let arrays = object.values.compactMap { $0 as? [Any] }
            if arrays.count == 1 { list = arrays[0] }
        }
        guard let items = list?.prefix(ClipboardAppLibraryReader.maxRecords), !items.isEmpty else {
            throw ReadError.notRecognized
        }
        if items.allSatisfy({ $0 is String }) {
            return GenericFile(format: .json, columns: ["text"], rows: items.map { [$0 as? String ?? ""] }, text: "")
        }
        let objects = items.compactMap { $0 as? [String: Any] }
        guard objects.count == items.count else { throw ReadError.notRecognized }
        let columns = Array(Set(objects.flatMap(\.keys))).sorted()
        let rows = objects.map { object in columns.map { scalar(object[$0]) } }
        return GenericFile(format: .json, columns: columns, rows: rows, text: "")
    }

    private static func scalar(_ value: Any?) -> String {
        switch value {
        case let string as String: string
        case let number as NSNumber: CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false")
            : number.stringValue
        default: ""
        }
    }

    // MARK: Text

    private static func blocks(of text: String, separator: TextSeparator) -> [String] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [String] = []
        var current: [String] = []
        func close() {
            let block = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !block.isEmpty { blocks.append(block) }
            current = []
        }
        for line in lines {
            let blank = line.trimmingCharacters(in: .whitespaces).isEmpty
            switch separator {
            case .blankLine:
                if blank { close() } else { current.append(line) }
            case .line:
                if !blank { blocks.append(line.trimmingCharacters(in: .whitespaces)) }
            case .dashes:
                if isRule(line) { close() } else { current.append(line) }
            }
        }
        close()
        return blocks
    }

    private static func isRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3, let first = trimmed.first, "-=*".contains(first) else { return false }
        return trimmed.allSatisfy { $0 == first }
    }

    // MARK: Dates and flags

    private static func isTruthy(_ value: String) -> Bool {
        ["1", "true", "yes", "y", "x", "pinned", "starred", "favorite", "fav"]
            .contains(value.lowercased().trimmingCharacters(in: .whitespaces))
    }

    /// Foundation formatters are safe to share for parsing; Swift cannot see it.
    private nonisolated(unsafe) static let isoWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated(unsafe) static let iso = ISO8601DateFormatter()
    private static let layouts: [DateFormatter] = [
        "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd", "MM/dd/yyyy HH:mm:ss", "MM/dd/yyyy HH:mm", "MM/dd/yyyy"
    ].map { layout in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = layout
        return formatter
    }

    public static func date(from text: String) -> Date? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let number = Double(value) {
            if number >= 1e11 { return Date(timeIntervalSince1970: number / 1000) }
            return number >= 1e8 ? Date(timeIntervalSince1970: number) : nil
        }
        if let date = isoWithFraction.date(from: value) ?? iso.date(from: value) { return date }
        for layout in layouts {
            if let date = layout.date(from: value) { return date }
        }
        return nil
    }
}
