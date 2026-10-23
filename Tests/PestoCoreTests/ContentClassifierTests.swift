// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("ContentClassifier")
struct ContentClassifierTests {
    @Test("classifies hex color (with #)")
    func whenHexWithHash_thenColor() {
        let result = ContentClassifier.classify(text: "#FF8800")
        #expect(result.type == .color)
    }

    @Test("classifies hex color (without #)")
    func whenHexWithoutHash_thenColor() {
        let result = ContentClassifier.classify(text: "FF8800")
        #expect(result.type == .color)
    }

    @Test("a bare run of digits is a number, not a colour")
    func whenOnlyDigitsWithoutHash_thenText() {
        #expect(ContentClassifier.classify(text: "123456").type == .text)
        #expect(ContentClassifier.classify(text: "20231234").type == .text)
        #expect(ContentClassifier.classify(text: " 0000000 ").type == .text)
    }

    @Test("a hash makes digits a colour")
    func whenDigitsWithHash_thenColor() {
        #expect(ContentClassifier.classify(text: "#123456").type == .color)
        #expect(ContentClassifier.classify(text: "#20231234").type == .color)
    }

    @Test("a three-digit reference such as an issue number or a status code is text, not a colour", arguments: [
        "#178", "#404", "#500", "#123"
    ])
    func whenHashAndThreeDifferingDigits_thenText(reference: String) {
        #expect(ContentClassifier.classify(text: reference).type == .text)
    }

    @Test("a repeated-digit shorthand is still a colour, and so is one with a letter", arguments: [
        "#000", "#111", "#999", "#1a2", "#F80"
    ])
    func whenShorthandIsReallyAColour_thenColor(hex: String) {
        #expect(ContentClassifier.classify(text: hex).type == .color)
    }

    @Test("a plain word that happens to spell six or eight hex letters is not a colour", arguments: [
        "decade", "facade", "deface", "deadbeef", "efface "
    ])
    func whenBareLettersOnly_thenText(word: String) {
        #expect(ContentClassifier.classify(text: word).type == .text)
    }

    @Test("a bare hex that mixes digits and letters is still a colour")
    func whenBareHexMixes_thenColor() {
        #expect(ContentClassifier.classify(text: "a1b2c3").type == .color)
        #expect(ContentClassifier.classify(text: "FF8800AA").type == .color)
    }

    @Test("classifies hex color with alpha channel")
    func whenHexWithAlpha_thenColor() {
        #expect(ContentClassifier.classify(text: "#FF8800AA").type == .color)
        #expect(ContentClassifier.classify(text: "#00000000").type == .color)
        #expect(ContentClassifier.classify(text: "#FFFFFFFF").type == .color)
    }

    @Test("classifies 3-char shorthand hex (#RGB)")
    func whenShortHex_thenColor() {
        #expect(ContentClassifier.classify(text: "#F80").type == .color)
        #expect(ContentClassifier.classify(text: "#abc").type == .color)
    }

    @Test("classifies rgb() color")
    func whenRGB_thenColor() {
        #expect(ContentClassifier.classify(text: "rgb(255, 87, 51)").type == .color)
        #expect(ContentClassifier.classify(text: "RGB(0, 128, 0)").type == .color)
    }

    @Test("classifies rgba() color")
    func whenRGBA_thenColor() {
        #expect(ContentClassifier.classify(text: "rgba(255, 87, 51, 0.5)").type == .color)
    }

    @Test("classifies hsl() color")
    func whenHSL_thenColor() {
        #expect(ContentClassifier.classify(text: "hsl(10, 100%, 60%)").type == .color)
        #expect(ContentClassifier.classify(text: "HSL(240, 50%, 40%)").type == .color)
    }

    @Test("classifies hsla() color")
    func whenHSLA_thenColor() {
        #expect(ContentClassifier.classify(text: "hsla(10, 100%, 60%, 0.8)").type == .color)
    }

    @Test("does not classify bare 3-char hex without hash as color")
    func whenBareShortHexNoHash_thenNotColor() {
        // "F80" without # is ambiguous — we conservatively leave it as text/code
        let result = ContentClassifier.classify(text: "F80")
        #expect(result.type != .color)
    }

    @Test("classifies https URL")
    func whenHTTPSURL_thenURL() {
        let result = ContentClassifier.classify(text: "https://example.com/foo")
        #expect(result.type == .url)
        #expect(result.extractedURL?.host == "example.com")
    }

    @Test("classifies file URL")
    func whenFileURL_thenURL() {
        let result = ContentClassifier.classify(text: "file:///Users/me/Documents/foo.txt")
        #expect(result.type == .url)
    }

    @Test("classifies Swift code")
    func whenSwiftCode_thenCode() {
        let code = """
        func greet(name: String) -> String {
            guard !name.isEmpty else { return "Anonymous" }
            return "Hello, \\(name)"
        }
        """
        let result = ContentClassifier.classify(text: code)
        #expect(result.type == .code)
        #expect(result.detectedLanguage == "swift")
    }

    @Test("an SVG document copied as text is code in the SVG language, with or without an XML header")
    func whenSVGSource_thenCodeInSVG() {
        let bare = "<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'><rect width='10' height='10'/></svg>"
        let withHeader = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!-- icon -->\n\(bare)"

        for source in [bare, withHeader, "\n  \(bare)\n"] {
            let result = ContentClassifier.classify(text: source)
            #expect(result.type == .code)
            #expect(result.detectedLanguage == ClipboardItem.svgLanguage)
        }
    }

    @Test("prose that mentions svg, or markup that only contains one, is not an SVG document")
    func whenSVGOnlyMentioned_thenNotSVG() {
        #expect(ContentClassifier.classify(text: "Export it as an <svg> next week.").detectedLanguage != "SVG")
        #expect(
            ContentClassifier.classify(text: "<div><svg width='1' height='1'></svg></div>").detectedLanguage != "SVG"
        )
    }

    @Test("classifies Python code")
    func whenPythonCode_thenCode() {
        let code = """
        def greet(name):
            if name is None:
                return "Anonymous"
            return f"Hello, {name}"

        import sys
        """
        let result = ContentClassifier.classify(text: code)
        #expect(result.type == .code)
        #expect(result.detectedLanguage == "python")
    }

    @Test("classifies JavaScript code")
    func whenJavaScriptCode_thenCode() {
        let code = """
        const greet = async (name) => {
            const trimmed = name?.trim();
            return trimmed || "Anonymous";
        };
        export default greet;
        """
        let result = ContentClassifier.classify(text: code)
        #expect(result.type == .code)
        #expect(result.detectedLanguage == "javascript")
    }

    @Test("plain English remains text")
    func whenPlainText_thenText() {
        let result = ContentClassifier.classify(text: "Pick up groceries on the way home")
        #expect(result.type == .text)
        #expect(result.detectedLanguage == nil)
    }

    @Test("empty string is text")
    func whenEmpty_thenText() {
        let result = ContentClassifier.classify(text: "")
        #expect(result.type == .text)
    }

    @Test("single keyword is not enough to be code")
    func whenSingleKeyword_thenText() {
        let result = ContentClassifier.classify(text: "I have a function for this")
        // "function" alone is not enough — needs ≥2 hits.
        #expect(result.type == .text)
    }

    // MARK: - Prose false-positive regression tests

    @Test("prose with 'let's' is not Swift code")
    func whenProseWithLets_thenText() {
        let prose = """
        Now let's also trim the shopping list to only what matters

        Then let's book the trip and plan a few quick wins / low hanging fruit

        We can also do a /review of the budget

        btw, the printer is still jamming, sometimes the page just comes out blank
        """
        let result = ContentClassifier.classify(text: prose)
        #expect(result.type == .text, "Prose containing 'let's' must not classify as Swift code")
    }

    @Test("short instructional prose is not JavaScript")
    func whenShortInstructional_thenText() {
        let prose = """
        Now let's also trim the shopping list to only what matters

        Then let's book the trip and plan a few quick wins / low hanging fruit
        """
        let result = ContentClassifier.classify(text: prose)
        #expect(result.type == .text, "Casual prose must not classify as JavaScript")
    }

    @Test("prose talking about 'class' and 'function' is not code")
    func whenProseWithCodeWords_thenText() {
        let prose = "The class started late but the function was great. We had a const debate about var names."
        let result = ContentClassifier.classify(text: prose)
        #expect(result.type == .text)
    }

    @Test("markdown code fence with language classifies as code")
    func whenMarkdownFence_thenCode() {
        let text = """
        Here is some Swift:
        ```swift
        let x = 5
        ```
        """
        let result = ContentClassifier.classify(text: text)
        #expect(result.type == .code)
    }

    @Test("Swift import statement is a strong anchor")
    func whenSwiftImport_thenCode() {
        let result = ContentClassifier.classify(text: "import Foundation\nimport SwiftUI\nlet greeting = \"hi\"")
        #expect(result.type == .code)
        #expect(result.detectedLanguage == "swift")
    }

    @Test("Go package declaration is a strong anchor")
    func whenGoPackage_thenCode() {
        let result = ContentClassifier.classify(text: "package main\n\nfunc main() { fmt.Println(\"hi\") }")
        #expect(result.type == .code)
        #expect(result.detectedLanguage == "go")
    }

    @Test("Python def is a strong anchor even without other keywords")
    func whenPythonDef_thenCode() {
        let result = ContentClassifier.classify(text: "def greet(name):\n    return f\"hi {name}\"")
        #expect(result.type == .code)
        #expect(result.detectedLanguage == "python")
    }

    @Test("shebang is a strong anchor")
    func whenShebang_thenCode() {
        let result = ContentClassifier.classify(text: "#!/usr/bin/env bash\necho hi")
        #expect(result.type == .code)
    }

    @Test(
        "a long copy that only looks like the start of SQL or code is classified in bounded time",
        .timeLimit(.minutes(1)),
        arguments: ["SELECT a ", "{ x "]
    )
    func whenALongCopyIsAdversarial_thenItIsClassifiedQuickly(unit: String) {
        let text = String(repeating: unit, count: 40_000)
        let clock = ContinuousClock()

        let elapsed = clock.measure { _ = ContentClassifier.classify(text: text) }

        #expect(elapsed < .seconds(3), "classifying took \(elapsed)")
    }

    @Test("#RGBA is a colour with a digit in it, or four equal characters", arguments: [
        "#f008", "#0f08", "#1a2b", "#ffff", "#0000", "#1111", "#FFFF"
    ])
    func whenHashRGBA_thenColor(hex: String) {
        #expect(ContentClassifier.classify(text: hex).type == .color)
    }

    @Test(
        "four characters after a hash that are only letters, or digits that differ, stay text (ADR 0002)",
        arguments: [
            "#cafe", "#face", "#abcd", "#dead", "#1234", "#2024", "#4042"
        ]
    )
    func whenHashFourAndAmbiguous_thenText(text: String) {
        #expect(ContentClassifier.classify(text: text).type == .text)
    }

    @Test(
        "a function-shaped wrapper around anything but colour numbers is text, not a colour (ADR 0002, R-01)",
        arguments: [
            "rgb(password=hunter2-Correct-Horse-Battery)",
            "hsl(AKIAIOSFODNN7EXAMPLE secret)",
            "rgba(token: abc123def456)",
            "rgb(\n255, 0, 0\n)",
            "rgb(1, 2, 3) and the card 4242 4242 4242 4242",
            "rgb(300, 0, 0)",
            "hsl(10, 200%, 60%)"
        ]
    )
    func whenFunctionalWrapperIsNotAColour_thenText(text: String) {
        #expect(ContentClassifier.classify(text: text).type != .color)
    }

    @Test("a very long rgb() wrapper is text")
    func whenFunctionalWrapperIsHuge_thenText() {
        let text = "rgb(" + String(repeating: "1, ", count: 2000) + "1)"
        #expect(ContentClassifier.classify(text: text).type != .color)
    }

    @Test("real functional colours stay colours", arguments: [
        "rgb(255 0 0 / 50%)", "rgb(100%, 0%, 0%)", "rgba(255, 87, 51, 0.5)", "hsla(10, 100%, 60%, 0.8)",
        "hsl(240deg 50% 40%)", "  rgb(0,128,0)\n"
    ])
    func whenFunctionalColour_thenColor(text: String) {
        #expect(ContentClassifier.classify(text: text).type == .color)
    }
}
