// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Fill-in snippets")
struct FillInSnippetTests {
    @Test("an input token with a default and multiline is read")
    func whenInputToken_thenFieldHasLabelDefaultAndKind() {
        let fields = FillInParser.fields(in: #"Hi {{input:Customer name default="Acme" multiline}}"#)

        #expect(fields == [SnippetField(label: "Customer name", kind: .text(multiline: true), defaultValue: "Acme")])
    }

    @Test("a choice offers its options and the first is the default")
    func whenChoiceToken_thenOptionsAreSplit() {
        let fields = FillInParser.fields(in: #"{{choice:Greeting options="Hi|Hello|Dear"}}"#)

        #expect(fields == [SnippetField(label: "Greeting", kind: .choice(["Hi", "Hello", "Dear"]), defaultValue: "Hi")])
    }

    @Test("an optional section is a field of its own, and the same label is asked once")
    func whenRepeatedLabelsAndSections_thenOneFieldEach() {
        let text = "{{input:Name}} and {{input:Name}}{{optional:Sign off}}Thanks {{input:Name}}{{/optional}}"

        let fields = FillInParser.fields(in: text)

        #expect(fields.map(\.label) == ["Name", "Sign off"])
        #expect(fields[1].kind == .optional)
    }

    @Test("a token with no label, an empty options list or a stray opener is not a field")
    func whenMalformed_thenNoField() {
        #expect(FillInParser.fields(in: "{{input:}} {{choice:X options=\"\"}} {{optional:Y}}no end").isEmpty)
        #expect(FillInParser.fields(in: "{{name}} {{date}}").isEmpty)
    }

    @Test("a default can hold a pipe and a single brace, since the value is quoted")
    func whenDefaultHoldsDelimiters_thenKept() {
        let fields = FillInParser.fields(in: #"{{input:Q default="a|b } c"}}"#)

        #expect(fields.first?.defaultValue == "a|b } c")
    }

    @Test("a field written back as a token reads back the same")
    func whenFieldSerialized_thenRoundTrips() {
        let fields = [
            SnippetField(label: "Name", kind: .text(multiline: false), defaultValue: nil),
            SnippetField(label: "Notes", kind: .text(multiline: true), defaultValue: "none"),
            SnippetField(label: "Greeting", kind: .choice(["Hi", "Dear"]), defaultValue: "Hi")
        ]
        for field in fields {
            #expect(FillInParser.fields(in: field.token) == [field])
        }
    }

    @Test("inserting an optional section writes both tags, so the sheet never leaves one open")
    func whenOptionalInserted_thenClosed() {
        let field = SnippetField(label: "PS", kind: .optional, defaultValue: nil)

        #expect(field.insertion == "{{optional:PS}}{{/optional}}")
        #expect(FillInParser.fields(in: field.insertion) == [field])
    }

    @Test("fills replace input and choice tokens in one pass, without expanding what was typed")
    func whenFilled_thenValuesInsertedLiterally() {
        let fills = SnippetFills(values: ["Name": "{{clipboard}}", "Greeting": "Dear"])

        let result = TemplateExpander.expansionWithCaret(
            of: #"{{choice:Greeting options="Hi|Dear"}} {{input:Name}}!{{cursor}}"#,
            isSnippet: true,
            fills: fills,
            clipboardProvider: { "SECRET" }
        )

        #expect(result?.text == "Dear {{clipboard}}!")
        #expect(result?.charactersAfterCursor == 0)
    }

    @Test("a repeated label takes the one value")
    func whenLabelRepeats_thenSameValueEverywhere() {
        let result = TemplateExpander.expansion(
            of: "{{input:Name}}, hello {{input:Name}}", isSnippet: true, fills: SnippetFills(values: ["Name": "Ana"])
        )

        #expect(result == "Ana, hello Ana")
    }

    @Test("an optional section is kept when included and dropped otherwise, including its fields")
    func whenOptionalSection_thenIncludedOrDropped() {
        let text = "Hi{{optional:PS}}\n\nPS: {{input:PS text}}{{/optional}}"

        let kept = TemplateExpander.expansion(
            of: text, isSnippet: true, fills: SnippetFills(values: ["PS text": "bye"], included: ["PS"])
        )
        let dropped = TemplateExpander.expansion(of: text, isSnippet: true, fills: SnippetFills())

        #expect(kept == "Hi\n\nPS: bye")
        #expect(dropped == "Hi")
    }

    @Test("without fills, defaults are used: the input default or nothing, the first choice, no optional text")
    func whenNoFills_thenDefaults() {
        let text = #"{{input:A default="x"}}|{{input:B}}|{{choice:C options="p|q"}}|{{optional:D}}z{{/optional}}"#

        #expect(TemplateExpander.expansion(of: text, isSnippet: true) == "x||p|")
    }

    @Test("the app token is the paste target's name")
    func whenAppToken_thenTargetName() {
        #expect(TemplateExpander
            .expansion(of: "Sent from {{app}}", isSnippet: true, targetApp: "Mail") == "Sent from Mail")
        #expect(TemplateExpander.expansion(of: "Sent from {{app}}", isSnippet: true) == "Sent from ")
    }

    @Test("a snippet whose only token is a fill-in is a snippet, and its fields are listed for the prompt")
    func whenOnlyFillIn_thenPromptNeeded() {
        #expect(TemplateExpander.containsPlaceholders("{{input:Name}}"))
        #expect(FillInParser.needsPrompt("{{input:Name}}"))
        #expect(!FillInParser.needsPrompt("{{date}} {{app}}"))
    }
}

@Suite("Fill-in prompt")
struct FillInPromptTests {
    private let fields = FillInParser.fields(
        in: #"{{input:Name default="Ana"}}{{choice:Tone options="warm|formal"}}{{optional:PS}}x{{/optional}}"#
    )

    @Test("the prompt starts from defaults, the first choice and optional sections off")
    func whenNothingRemembered_thenDefaults() {
        let fills = SnippetFills.initial(for: fields)

        #expect(fills.values == ["Name": "Ana", "Tone": "warm"])
        #expect(fills.included.isEmpty)
    }

    @Test("a remembered value wins, unless a choice is no longer offered")
    func whenRemembered_thenUsedIfStillValid() {
        let fills = SnippetFills.initial(for: fields, remembered: ["Name": "Bo", "Tone": "gone", "PS": "1"])

        #expect(fills.values == ["Name": "Bo", "Tone": "warm"])
        #expect(fills.included == ["PS"])
    }

    @Test("several snippets ask each label once")
    func whenManySnippets_thenFieldsMerged() {
        let merged = FillInParser.fields(inAll: ["{{input:A}}{{input:B}}", "{{input:B}}{{input:C}}"])

        #expect(merged.map(\.label) == ["A", "B", "C"])
    }
}

@Suite("Fill-in imports")
struct FillInImportTests {
    private func text(_ json: String) throws -> String? {
        try SnippetPackReader.read(Data(json.utf8)).snippets.first?.text
    }

    @Test("Raycast arguments become inputs and choices")
    func whenRaycastArgument_thenConverted() throws {
        let raw = #"Hi {argument name=\"Who\"}, {argument name=\"Tone\" options=\"warm, formal\"} {argument}"#
        let result = try text(#"[{"text":"\#(raw)"}]"#)

        #expect(result == #"Hi {{input:Who}}, {{choice:Tone options="warm|formal"}} {{input:Argument}}"#)
    }

    @Test("TextExpander fill-ins become inputs, choices and optional sections")
    func whenTextExpanderFillIns_thenConverted() throws {
        let raw = "%filltext:name=Client:default=Acme% %fillarea:name=Notes% "
            + "%fillpopup:name=Greeting:default=Hello:Hi:Hello% %fillpart:name=PS%P.S.%fillpartend%"
        let json = #"[{"text":"\#(raw)"}]"#

        #expect(try text(json) == #"{{input:Client default="Acme"}} {{input:Notes multiline}} "#
            + #"{{choice:Greeting options="Hi|Hello" default="Hello"}} {{optional:PS}}P.S.{{/optional}}"#)
    }

    @Test("an imported argument is no longer counted as unsupported")
    func whenArgument_thenNotCounted() throws {
        let pack = try SnippetPackReader.read(Data(#"[{"text":"{argument name=\"X\"}"}]"#.utf8))

        #expect(pack.withUnsupportedTokens == 0)
        #expect(pack.snippets.count == 1)
    }
}

@Suite("Fill-ins in a stack")
struct StackSnippetTests {
    private func item(_ text: String) -> PasteStack.Item {
        PasteStack.Item(
            previewText: text,
            payloadKind: .text(text),
            pasteboardData: Data(text.utf8),
            pasteboardType: "text/plain"
        )
    }

    @Test("a stack asks for the fields of its snippets only, each label once")
    func whenStackHasSnippets_thenFieldsAreMerged() {
        let items = [item("{{input:A}}"), item("{{input:B}} {{input:A}}"), item("{{input:Z}}")]

        let fields = PasteStack.fields(of: items, isSnippet: [true, true, false])

        #expect(fields.map(\.label) == ["A", "B"])
    }

    @Test("an item is expanded with the answers, and its bytes follow its text")
    func whenExpanded_thenTextAndBytesAgree() {
        let result = item("Hi {{input:A}} in {{app}}").expandingSnippet(
            fills: SnippetFills(values: ["A": "Ana"]), targetApp: "Mail", clipboard: ""
        )

        #expect(result.payloadKind == .text("Hi Ana in Mail"))
        #expect(result.pasteboardData == Data("Hi Ana in Mail".utf8))
        #expect(result.richPayload == nil)
    }
}
