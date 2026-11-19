// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The keyboard's built-in starters")
struct KeyboardStarterTests {
    private let noon = Date(timeIntervalSince1970: 1_795_000_000)

    @Test("there are five, in the order the keyboard shows them")
    func whenListed_thenFiveInOrder() {
        #expect(KeyboardStarter.allCases == [.date, .time, .isoDate, .weekday, .uuid])
    }

    @Test("each expands to what the same snippet placeholder gives")
    func whenExpanded_thenMatchesTheTemplateExpander() {
        for (starter, token) in [
            (KeyboardStarter.date, "{{date}}"), (.time, "{{time}}"), (.isoDate, "{{isodate}}"),
            (.weekday, "{{weekday}}")
        ] {
            let expected = TemplateExpander.expansion(of: token, isSnippet: true, at: noon, clipboardProvider: { "" })
            #expect(starter.text(at: noon) == expected)
            #expect(!starter.text(at: noon).isEmpty)
            #expect(!starter.text(at: noon).contains("{{"))
        }
    }

    @Test("the ISO date is year-month-day")
    func whenISODate_thenYearMonthDay() {
        #expect(KeyboardStarter.isoDate.text(at: noon).wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil)
    }

    @Test("a UUID is new on every tap")
    func whenUUIDTappedTwice_thenTwoValues() {
        let first = KeyboardStarter.uuid.text(at: noon)
        let second = KeyboardStarter.uuid.text(at: noon)
        #expect(first != second)
        #expect(UUID(uuidString: first) != nil)
        #expect(first == first.lowercased())
    }

    @Test("each has a title to show on its key")
    func whenTitled_thenNotEmpty() {
        #expect(KeyboardStarter.allCases.allSatisfy { !$0.title.isEmpty })
        #expect(Set(KeyboardStarter.allCases.map(\.title)).count == KeyboardStarter.allCases.count)
    }
}
