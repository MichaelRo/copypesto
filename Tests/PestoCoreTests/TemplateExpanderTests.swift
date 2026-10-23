// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("TemplateExpander")
struct TemplateExpanderTests {
    private static let fixedDate: Date = {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 5
        comps.day = 15
        comps.hour = 14
        comps.minute = 30
        comps.second = 0
        comps.timeZone = TimeZone(identifier: "UTC")
        // Safe: fixed literal components always produce a valid date.
        return Calendar.current.date(from: comps) ?? Date(timeIntervalSince1970: 1_747_317_000)
    }()

    @Test
    func noPlaceholders_returnsOriginal() {
        let text = "Hello, world!"
        #expect(TemplateExpander.expand(text, at: Self.fixedDate) == text)
    }

    @Test
    func date_isReplaced() {
        let result = TemplateExpander.expand("Today: {{date}}", at: Self.fixedDate)
        #expect(!result.contains("{{date}}"))
        #expect(result.contains("Today: "))
        #expect(result.count > "Today: ".count)
    }

    @Test
    func time_isReplaced() {
        let result = TemplateExpander.expand("Now: {{time}}", at: Self.fixedDate)
        #expect(!result.contains("{{time}}"))
    }

    @Test
    func datetime_isReplaced() {
        let result = TemplateExpander.expand("{{datetime}}", at: Self.fixedDate)
        #expect(!result.contains("{{datetime}}"))
        #expect(!result.isEmpty)
    }

    @Test
    func cursor_isRemoved() {
        let result = TemplateExpander.expand("Hello{{cursor}} world", at: Self.fixedDate)
        #expect(result == "Hello world")
    }

    @Test
    func multiplePlaceholders_allExpanded() {
        let result = TemplateExpander.expand("{{date}} at {{time}}{{cursor}}", at: Self.fixedDate)
        #expect(!result.contains("{{"))
        #expect(!result.isEmpty)
    }

    @Test
    func unknownPlaceholder_leftUntouched() {
        let result = TemplateExpander.expand("Hello {{name}}", at: Self.fixedDate)
        #expect(result == "Hello {{name}}")
    }

    @Test
    func containsPlaceholders_detectsPresence() {
        #expect(TemplateExpander.containsPlaceholders("{{date}}"))
        #expect(!TemplateExpander.containsPlaceholders("plain text"))
    }

    @Test("only a snippet is expanded: other text that happens to contain double braces pastes unchanged")
    func whenNotASnippet_thenNothingIsExpanded() {
        let text = "{{date}} in a Helm chart"
        #expect(TemplateExpander.expansion(of: text, isSnippet: false) == nil)
        #expect(TemplateExpander.expansion(of: text, isSnippet: true) != nil)
        #expect(TemplateExpander.expansion(of: "no placeholders", isSnippet: true) == nil)
    }

    @Test
    func caret_isTheCharactersAfterTheCursor() {
        let result = TemplateExpander.expansionWithCaret(of: "Hi {{cursor}},\nBye", isSnippet: true, at: Self.fixedDate)

        #expect(result?.text == "Hi ,\nBye")
        #expect(result?.charactersAfterCursor == 5)
    }

    @Test
    func caret_countsAnEmojiAsOneCharacter() {
        let result = TemplateExpander.expansionWithCaret(of: "a{{cursor}}b👩🏽‍💻", isSnippet: true, at: Self.fixedDate)

        #expect(result?.charactersAfterCursor == 2)
    }

    @Test
    func caret_isTheFirstCursorWhenThereAreSeveral() {
        let result = TemplateExpander.expansionWithCaret(
            of: "A{{cursor}}B{{cursor}}C",
            isSnippet: true,
            at: Self.fixedDate
        )

        #expect(result?.text == "ABC")
        #expect(result?.charactersAfterCursor == 2)
    }

    @Test
    func caret_isCountedAfterDatesAreFilledIn() {
        let result = TemplateExpander.expansionWithCaret(
            of: "{{date}} {{cursor}}!",
            isSnippet: true,
            at: Self.fixedDate
        )

        #expect(result?.charactersAfterCursor == 1)
    }

    @Test
    func caret_isNilWithoutACursor() {
        let result = TemplateExpander.expansionWithCaret(of: "Today {{date}}", isSnippet: true, at: Self.fixedDate)

        #expect(result?.charactersAfterCursor == nil)
        #expect(result != nil)
    }

    @Test
    func caret_isNilForTextThatIsNotASnippet() {
        #expect(TemplateExpander.expansionWithCaret(of: "a {{cursor}} b", isSnippet: false) == nil)
    }

    @Test("{{clipboard}} expands live clipboard text in one pass without expanding tokens inside the clipboard")
    func whenClipboardPlaceholder_thenExpandsWithoutRecursingIntoClipboardTokens() {
        let result = TemplateExpander.expand(
            "Quoted: {{clipboard}} on {{isodate}}",
            at: Self.fixedDate,
            clipboardProvider: { " literal {{date}} and {{cursor}} " }
        )
        #expect(result == "Quoted:  literal {{date}} and {{cursor}}  on 2026-05-15")

        let withCaret = TemplateExpander.expansionWithCaret(
            of: "Clip: {{clipboard}} -> {{cursor}}done",
            isSnippet: true,
            at: Self.fixedDate,
            clipboardProvider: { "{{cursor}}" }
        )
        #expect(withCaret?.text == "Clip: {{cursor}} -> done")
        #expect(withCaret?.charactersAfterCursor == 4)
    }

    @Test("{{isodate}}, {{weekday}}, and {{date+Nd}}/{{date-Nd}} format dates deterministically")
    func whenISODateAndWeekdayAndRelativeDate_thenFormattedDeterministically() {
        let iso = TemplateExpander.expand("{{isodate}}", at: Self.fixedDate)
        #expect(iso == "2026-05-15")

        let weekday = TemplateExpander.expand("{{weekday}}", at: Self.fixedDate)
        #expect(!weekday.isEmpty)
        #expect(!weekday.contains("{{"))

        let tomorrowDate = Calendar.current.date(byAdding: .day, value: 1, to: Self.fixedDate) ?? Self.fixedDate
        let yesterdayDate = Calendar.current.date(byAdding: .day, value: -1, to: Self.fixedDate) ?? Self.fixedDate
        let expectedTomorrow = TemplateExpander.expand("{{date}}", at: tomorrowDate)
        let expectedYesterday = TemplateExpander.expand("{{date}}", at: yesterdayDate)

        #expect(TemplateExpander.expand("{{date+1d}}", at: Self.fixedDate) == expectedTomorrow)
        #expect(TemplateExpander.expand("{{date-1d}}", at: Self.fixedDate) == expectedYesterday)
    }

    @Test("{{uuid}} expands to a lowercase UUID string")
    func whenUUIDPlaceholder_thenProducesValidLowercaseUUID() {
        let expanded = TemplateExpander.expand("{{uuid}}", at: Self.fixedDate)
        #expect(UUID(uuidString: expanded) != nil)
        #expect(expanded == expanded.lowercased())
    }

    @Test("only text with the clipboard placeholder asks for the live clipboard (P-03)", arguments: [
        ("hello {{clipboard}} world", true), ("{{clipboard}}", true), ("{{date}} {{cursor}}", false),
        ("plain text", false), ("{{ clipboard }}", false)
    ])
    func whenText_thenReferencesClipboardOnlyForThePlaceholder(text: String, expected: Bool) {
        #expect(TemplateExpander.referencesClipboard(in: text) == expected)
    }
}
