// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("CSV and TSV to a JSON array of objects")
struct CSVTableTests {
    private func json(_ text: String) -> String? {
        CSVTable.parse(text)?.jsonText()
    }

    private func objects(_ text: String) throws -> [[String: String]]? {
        guard let output = json(text) else { return nil }
        return try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [[String: String]]
    }

    // MARK: What it writes

    @Test("comma separated rows become objects in header order, two-space indent, every value a string")
    func whenCommaSeparated_thenIndentedObjects() {
        let expected = "[\n  {\n    \"name\": \"Ana\",\n    \"age\": \"30\"\n  },\n  {\n    \"name\": \"Bo\","
            + "\n    \"age\": \"25\"\n  }\n]"
        #expect(json("name,age\nAna,30\nBo,25") == expected)
    }

    @Test("a tab separated table, as copied from a spreadsheet, reads the same way")
    func whenTabSeparated_thenSameObjects() throws {
        let rows = try objects("name\tcity\nAna\tOslo, Norway\nBo\tLyon\n")
        #expect(rows == [["name": "Ana", "city": "Oslo, Norway"], ["name": "Bo", "city": "Lyon"]])
    }

    @Test("a leading zero and a long number stay exactly as typed")
    func whenNumbersLookLikeNumbers_thenStrings() throws {
        let rows = try objects("zip,id\n02134,12345678901234567890")
        #expect(rows == [["zip": "02134", "id": "12345678901234567890"]])
    }

    @Test("empty cells are empty strings, including a trailing one")
    func whenCellsAreEmpty_thenEmptyStrings() throws {
        let rows = try objects("a,b,c\n1,,3\n,,\n4,5,")
        #expect(rows == [
            ["a": "1", "b": "", "c": "3"],
            ["a": "", "b": "", "c": ""],
            ["a": "4", "b": "5", "c": ""]
        ])
    }

    @Test("unicode, emoji and combining marks survive, in keys and in values")
    func whenUnicode_thenUnchanged() throws {
        let rows = try objects("名前,emoji,café\nさくら,🍕👩‍👩‍👧,e\u{301}")
        #expect(rows == [["名前": "さくら", "emoji": "🍕👩‍👩‍👧", "café": "e\u{301}"]])
    }

    @Test("unquoted cells lose the spaces around them; quoted ones keep them")
    func whenSpaces_thenOnlyUnquotedTrimmed() throws {
        let rows = try objects("a , b\n 1 , \" 2 \" ")
        #expect(rows == [["a": "1", "b": " 2 "]])
    }

    // MARK: Quoting and line ends

    @Test("a quoted cell can hold the delimiter, a doubled quote and a line break")
    func whenQuoted_thenReadLiterally() throws {
        let rows = try objects("q,note\n\"a, b\",\"say \"\"hi\"\"\"\nx,\"line1\nline2\"")
        #expect(rows == [["q": "a, b", "note": "say \"hi\""], ["q": "x", "note": "line1\nline2"]])
    }

    @Test("CRLF, lone CR, a byte order mark, blank lines and a final newline are all ordinary")
    func whenLineEndsVary_thenSameRows() throws {
        let expected = [["a": "1", "b": "2"], ["a": "3", "b": "4"]]
        #expect(try objects("a,b\r\n1,2\r\n3,4\r\n") == expected)
        #expect(try objects("a,b\r1,2\r3,4") == expected)
        #expect(try objects("\u{FEFF}a,b\n1,2\n\n   \n3,4\n\n") == expected)
    }

    @Test("control characters and backslashes are escaped in the JSON")
    func whenControlCharacters_thenEscaped() throws {
        let output = try #require(json("a,b\n\"t\tab\",\"back\\slash\u{1}\""))
        #expect(output.contains("\"t\\tab\""))
        #expect(output.contains("\"back\\\\slash\\u0001\""))
        #expect(try objects("a,b\n\"t\tab\",\"back\\slash\u{1}\"") == [["a": "t\tab", "b": "back\\slash\u{1}"]])
    }

    @Test("a quote inside an unquoted cell is just a quote")
    func whenQuoteInsideUnquotedCell_thenLiteral() throws {
        let rows = try objects("size,item\n5\" pipe,joint")
        #expect(rows == [["size": "5\" pipe", "item": "joint"]])
    }

    // MARK: What is not a table

    @Test("these are not tables", arguments: [
        "one column\nstill one\nand one",
        "name,age",
        "name,age\n",
        "a,b\n1,2,3",
        "a,b\n1",
        "a,a\n1,2",
        "a,\n1,2",
        "a,b\n\"unterminated,2\n3,4",
        "a,b\n\"x\"y,2",
        "Well, yes.\nOkay, no.",
        "Hello, world!\nWait, what?",
        "{\"a\":1,\"b\":2}\n{\"a\":3,\"b\":4}",
        "just some words",
        ""
    ])
    func whenNotATable_thenNil(text: String) {
        #expect(CSVTable.parse(text) == nil)
    }

    @Test("a header that is a sentence, not a name, is not a table")
    func whenHeaderIsLong_thenNil() {
        let long = String(repeating: "x", count: 41)
        #expect(CSVTable.parse("\(long),b\n1,2") == nil)
        #expect(CSVTable.parse("\(String(repeating: "x", count: 40)),b\n1,2") != nil)
    }

    @Test("a table wider than the limit is not one")
    func whenTooManyColumns_thenNil() {
        let header = (0...CSVTable.maxColumns).map { "c\($0)" }.joined(separator: ",")
        let row = (0...CSVTable.maxColumns).map { _ in "1" }.joined(separator: ",")
        #expect(CSVTable.parse("\(header)\n\(row)") == nil)
    }

    // MARK: Bounds

    @Test("input over the byte limit is refused without being read")
    func whenInputTooBig_thenNil() {
        let big = "a,b\n" + String(repeating: "1,2\n", count: CSVTable.maxInputBytes / 4 + 1)
        #expect(CSVTable.parse(big) == nil)
    }

    @Test("output over its limit is refused, and stops early")
    func whenOutputTooBig_thenNil() throws {
        let table = try #require(CSVTable.parse("a,b\n1,2\n3,4"))
        #expect(table.jsonText(maxBytes: 20) == nil)
        #expect(table.jsonText() != nil)
    }

    @Test("a sample of the first rows is enough to say a long table is one")
    func whenSampled_thenOnlyTheFirstRowsAreRead() throws {
        let body = String(repeating: "1,2\n", count: 1000) + "ragged,row,here\n"
        let text = "a,b\n" + body
        #expect(CSVTable.parse(text) == nil)
        let sample = try #require(CSVTable.parse(text, maxRows: 20))
        #expect(sample.rows.count == 19)
    }

    @Test("one megabyte of rows converts well inside a frame")
    func whenAMegabyte_thenFast() throws {
        let line = "Ana Example,ana@example.com,\"Oslo, Norway\",2024-01-01,123.45\n"
        var text = "name,email,city,date,amount\n"
        while text.utf8.count < 990_000 {
            text += line
        }
        let start = ContinuousClock.now
        let output = try #require(CSVTable.parse(text)?.jsonText())
        let elapsed = BestOf.within(.milliseconds(250), first: ContinuousClock.now - start) {
            _ = CSVTable.parse(text)?.jsonText()
        }
        #expect(output.utf8.count > text.utf8.count)
        if ProcessInfo.processInfo.environment["CI"] == nil { #expect(elapsed < .milliseconds(250), "took \(elapsed)") }
    }
}
