// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("JSON entry: indent a compact document, keep it as it was")
struct JSONDocumentTests {
    @Test("keys stay in the order they were written, with two-space indent and one space after the colon")
    func whenCompact_thenIndentedInSameOrder() {
        let out = JSONDocument.formatted("{\"b\":1,\"a\":[true,null,\"x\"],\"c\":{\"d\":2}}")
        let expected = "{\n  \"b\": 1,\n  \"a\": [\n    true,\n    null,\n    \"x\"\n  ],\n  \"c\": {"
            + "\n    \"d\": 2\n  }\n}"
        #expect(out == expected)
    }

    @Test("numbers keep every digit and their spelling")
    func whenBigOrOddNumbers_thenUnchanged() throws {
        let out = try #require(JSONDocument
            .formatted("[12345678901234567890,1.50,1e3,-0.0,0.1000000000000000055511151231257827]"))
        #expect(out.contains("12345678901234567890"))
        #expect(out.contains("1.50"))
        #expect(out.contains("1e3"))
        #expect(out.contains("-0.0"))
        #expect(out.contains("0.1000000000000000055511151231257827"))
    }

    @Test("braces, commas, colons and escaped quotes inside a string are not structure")
    func whenStringsHoldPunctuation_thenUntouched() throws {
        let source = "{\"k\":\"a,b:{c}[d]\\\"e\\\\\",\"u\":\"\\u00e9 é 🍕\"}"
        let out = try #require(JSONDocument.formatted(source))
        #expect(out == "{\n  \"k\": \"a,b:{c}[d]\\\"e\\\\\",\n  \"u\": \"\\u00e9 é 🍕\"\n}")
    }

    @Test("empty objects and arrays stay on one line")
    func whenEmptyContainers_thenCompact() {
        #expect(JSONDocument.formatted("{\"a\":{},\"b\":[ ]}") == "{\n  \"a\": {},\n  \"b\": []\n}")
    }

    @Test("whitespace that is already there is not kept")
    func whenSpread_thenRespaced() {
        #expect(JSONDocument.formatted("  {\"a\"  :\n\t1 , \"b\":2}\n") == "{\n  \"a\": 1,\n  \"b\": 2\n}")
    }

    @Test("a document that is already indented this way offers nothing, with or without a final newline")
    func whenAlreadyFormatted_thenNil() {
        let pretty = "{\n  \"a\": 1\n}"
        #expect(JSONDocument.formatted(pretty) == nil)
        #expect(JSONDocument.formatted(pretty + "\n") == nil)
    }

    @Test("these are not documents", arguments: [
        "", "just words", "42", "\"string\"", "true", "{broken", "{\"a\":1,}", "[1,2", "{'a':1}",
        "{\"a\":1} trailing", "[1,2]\n[3,4]", "{\"a\":NaN}"
    ])
    func whenNotADocument_thenNil(text: String) {
        #expect(JSONDocument.formatted(text) == nil)
    }

    @Test("input over the limit is not read")
    func whenTooBig_thenNil() {
        let body = String(repeating: "1,", count: JSONDocument.maxInputBytes / 2)
        #expect(JSONDocument.formatted("[" + body + "1]") == nil)
    }

    @Test("output over the limit is refused, so deep nesting cannot swell")
    func whenOutputWouldBeHuge_thenNil() {
        let depth = 400
        let nested = String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
        #expect(JSONDocument.formatted(nested, maxOutputBytes: 1000) == nil)
        #expect(JSONDocument.formatted("[1,2]", maxOutputBytes: 3) == nil)
    }

    @Test("one megabyte formats well inside a frame")
    func whenAMegabyte_thenFast() throws {
        var text = "["
        while text.utf8.count < 950_000 {
            text += "{\"name\":\"Ana\",\"tags\":[\"a\",\"b\"],\"n\":12345},"
        }
        text += "{}]"
        let start = ContinuousClock.now
        let out = try #require(JSONDocument.formatted(text))
        let elapsed = ContinuousClock.now - start
        #expect(out.utf8.count > text.utf8.count)
        if ProcessInfo.processInfo.environment["CI"] == nil { #expect(elapsed < .milliseconds(400), "took \(elapsed)") }
    }
}
