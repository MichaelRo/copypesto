// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Other File import")
struct GenericFileReaderTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func read(_ text: String, _ ext: String) throws -> GenericFile {
        try GenericFileReader.read(Data(text.utf8), fileExtension: ext)
    }

    private func texts(_ library: ClipboardAppLibrary) -> [String] {
        library.records.compactMap { record in
            record.representations.first.flatMap { Data(base64Encoded: $0.dataBase64) }.flatMap {
                String(data: $0, encoding: .utf8)
            }
        }
    }

    private func library(_ file: GenericFile, _ mapping: GenericFileMapping? = nil) -> ClipboardAppLibrary {
        GenericFileReader.library(from: file, mapping: mapping ?? GenericFileMapping.detected(for: file), now: now)
    }

    // MARK: CSV

    @Test("a CSV has its header as columns and its rows as clips")
    func whenCSV_thenColumnsAndRows() throws {
        let file = try read("Content,Copied at\nhello,2026-01-02\nworld,2026-01-03\n", "csv")
        #expect(file.format == .csv)
        #expect(file.columns == ["Content", "Copied at"])
        #expect(texts(library(file)) == ["hello", "world"])
    }

    @Test("quotes, doubled quotes and line breaks inside a quoted cell stay in the clip")
    func whenQuoted_thenKept() throws {
        let file = try read("text\n\"a, b\"\n\"say \"\"hi\"\"\"\n\"line one\nline two\"\n", "csv")
        #expect(texts(library(file)) == ["a, b", "say \"hi\"", "line one\nline two"])
    }

    @Test("CRLF, CR, a byte order mark, semicolons and tabs are all read")
    func whenOtherDialects_thenRead() throws {
        #expect(try texts(library(read("\u{FEFF}text\r\none\r\ntwo\r\n", "csv"))) == ["one", "two"])
        #expect(try texts(library(read("text\rone\rtwo", "csv"))) == ["one", "two"])
        #expect(try texts(library(read("text;when\none;1\ntwo;2\n", "csv"))) == ["one", "two"])
        #expect(try texts(library(read("text\twhen\none\t1\ntwo\t2\n", "tsv"))) == ["one", "two"])
    }

    @Test("short and long rows are tolerated, and an empty clip is counted as left out")
    func whenRagged_thenTolerated() throws {
        let file = try read("text,when,pinned\nkept\nalso,2026-01-01,no,extra,cells\n,2026-01-01,no\n", "csv")
        let result = library(file)
        #expect(texts(result) == ["kept", "also"])
        #expect(result.skipped == 1)
    }

    @Test("the text column is picked by name, whatever its position or case")
    func whenHeaderNames_thenDetected() throws {
        let file = try read("ID,CLIP,Created,Favorite\n1,alpha,2026-01-01,yes\n2,beta,2026-01-02,no\n", "csv")
        let mapping = GenericFileMapping.detected(for: file)
        #expect(mapping.textColumn == 1)
        #expect(mapping.dateColumn == 2)
        #expect(mapping.pinnedColumn == 3)
        let result = library(file, mapping)
        #expect(texts(result) == ["alpha", "beta"])
        #expect(result.records.map { $0.pinboard != nil } == [true, false])
    }

    @Test("with no recognizable name the first column is the text and nothing else is read")
    func whenNoNames_thenFirstColumn() throws {
        let file = try read("a,b\nx,secret\n", "csv")
        let mapping = GenericFileMapping.detected(for: file)
        #expect(mapping.textColumn == 0 && mapping.dateColumn == nil && mapping.pinnedColumn == nil)
    }

    // MARK: JSON

    @Test("JSON: an array of strings, an array of objects, and an object holding one array")
    func whenJSON_thenRead() throws {
        #expect(try texts(library(read(#"["one","two"]"#, "json"))) == ["one", "two"])
        let objects = try read(#"[{"text":"a","date":1700000000},{"text":"b","extra":{"nested":1}}]"#, "json")
        #expect(objects.columns.contains("text") && objects.columns.contains("date"))
        #expect(texts(library(objects)) == ["a", "b"])
        #expect(try texts(library(read(#"{"items":["x","y"]}"#, "json"))) == ["x", "y"])
    }

    @Test(
        "JSON that is not a list of clips is not recognized",
        arguments: ["{}", "42", "[[1,2]]", "{\"a\":1,\"b\":2}", "not json"]
    )
    func whenNotClips_thenNotRecognized(text: String) {
        #expect(throws: GenericFileReader.ReadError.notRecognized) { _ = try read(text, "json") }
    }

    // MARK: Text

    @Test("a text file splits on blank lines, on every line, or on lines of dashes", arguments: [
        (TextSeparator.blankLine, ["first\nstill first", "second"]),
        (TextSeparator.line, ["first", "still first", "second"]),
        (TextSeparator.dashes, ["first\nstill first\n\nsecond"])
    ])
    func whenText_thenSplit(separator: TextSeparator, expected: [String]) throws {
        let file = try read("first\nstill first\n\nsecond\n", "txt")
        var mapping = GenericFileMapping.detected(for: file)
        mapping.separator = separator
        #expect(texts(library(file, mapping)) == expected)
    }

    @Test("dashes between clips split on a line of three or more")
    func whenDashLines_thenSplit() throws {
        let file = try read("one\n---\ntwo\n=====\nthree", "txt")
        var mapping = GenericFileMapping.detected(for: file)
        mapping.separator = .dashes
        #expect(texts(library(file, mapping)) == ["one", "two", "three"])
    }

    // MARK: Dates and order

    @Test("dates are read as seconds, milliseconds, ISO 8601 or common layouts, and a missing one is the import time")
    func whenDates_thenParsed() {
        #expect(GenericFileReader.date(from: "1700000000") == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(GenericFileReader.date(from: "1700000000000") == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(GenericFileReader.date(from: "2026-01-02T03:04:05Z") == Date(timeIntervalSince1970: 1_767_323_045))
        #expect(GenericFileReader.date(from: "2026-01-02T03:04:05.250Z") != nil)
        #expect(GenericFileReader.date(from: "2026-01-02 03:04:05") != nil)
        #expect(GenericFileReader.date(from: "2026-01-02") != nil)
        #expect(GenericFileReader.date(from: "01/02/2026 03:04") != nil)
        #expect(GenericFileReader.date(from: "yesterday") == nil)
        #expect(GenericFileReader.date(from: "") == nil)
    }

    @Test("rows with no date keep the file's order, the later rows being newer, and never lie in the future")
    func whenNoDates_thenFileOrder() throws {
        let file = try read("text\na\nb\nc\n", "csv")
        let stamps = library(file).records.map(\.timestamp)
        #expect(stamps == stamps.sorted())
        #expect(Set(stamps).count == 3)
        #expect(stamps.allSatisfy { $0 <= now })
    }

    // MARK: Limits and hostile files

    @Test("a file over the size limit is refused before it is read")
    func whenTooLarge_thenRefused() {
        #expect(throws: GenericFileReader.ReadError.tooLarge) {
            _ = try GenericFileReader.read(Data(repeating: 0x61, count: 101), fileExtension: "txt", maxBytes: 100)
        }
    }

    @Test("rows past the cap are not read, and a clip over the per-clip cap is left out")
    func whenHuge_thenBounded() throws {
        let rows = (0..<(ClipboardAppLibraryReader.maxRecords + 50)).map { "row\($0)" }.joined(separator: "\n")
        let file = try read("text\n" + rows, "csv")
        let result = library(file)
        #expect(result.records.count == ClipboardAppLibraryReader.maxRecords)

        let big = String(repeating: "x", count: GenericFileReader.maxClipCharacters + 1)
        let oversized = try read("text\nok\n\(big)\n", "csv")
        let kept = library(oversized)
        #expect(texts(kept) == ["ok"])
        #expect(kept.skipped == 1)
    }

    @Test("binary data and invalid text are not recognized")
    func whenBinary_thenNotRecognized() {
        let junk = Data([0xFF, 0xFE, 0x00, 0x01, 0x80, 0x81, 0xC0, 0xC1, 0xF5])
        #expect(throws: GenericFileReader.ReadError.notRecognized) {
            _ = try GenericFileReader.read(junk, fileExtension: "csv")
        }
    }

    @Test("an unclosed quote and a long run of delimiters are read in well under a frame")
    func whenAdversarial_thenFast() {
        let unclosed = "text\n\"" + String(repeating: "a,\"\"b\n", count: 20_000)
        let delimiters = "text\n" + String(repeating: ",", count: 200_000)
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = try? read(unclosed, "csv")
            _ = try? read(delimiters, "csv")
        }
        #expect(elapsed < .milliseconds(500))
    }

    @Test("an unknown extension is sniffed: a JSON list, a table, or plain text")
    func whenUnknownExtension_thenSniffed() throws {
        #expect(try read(#"["a"]"#, "dat").format == .json)
        #expect(try read("text,when\na,1\nb,2\n", "dat").format == .csv)
        #expect(try read("just some words\n\nand more", "dat").format == .text)
    }
}
