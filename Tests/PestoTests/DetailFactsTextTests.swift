// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import Testing
@testable import Pesto

@Suite("The words under the hover card's body")
struct DetailFactsTextTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private func text(_ fact: DetailFact) -> String {
        DetailFactsText.text(for: fact, now: Date(timeIntervalSince1970: 1_800_000_000), calendar: calendar)
    }

    @Test("counts agree with their noun, one and many")
    func counts_usePluralForms() {
        #expect(text(.lines(1)) == "1 line")
        #expect(text(.lines(3)) == "3 lines")
        #expect(text(.files(1)) == "1 file")
        #expect(text(.files(5)) == "5 files")
        #expect(text(.characters(1)) == "1 character")
        #expect(text(.characters(98)) == "98 characters")
    }

    @Test("a cut clip says how much of it is shown")
    func charactersShown_saysTheFraction() {
        #expect(text(.charactersShown(shown: 4000, total: 12_480)).contains("of"))
        #expect(text(.charactersShown(shown: 4000, total: 12_480)).hasSuffix("characters"))
    }

    @Test("a colour reads as RGB, a collection as where it is")
    func colourAndCollection() {
        #expect(text(.rgb(red: 82, green: 157, blue: 110)) == "RGB 82, 157, 110")
        #expect(text(.collection("Recipes")) == "In Recipes")
        #expect(text(.fromPhone) == "From iPhone")
    }

    @Test("a date reads in the locale and time zone it is given, whatever this Mac uses")
    func when_followsTheGivenLocaleAndZone() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let now = date.addingTimeInterval(86_400 * 400)
        func read(_ identifier: String) -> String {
            DetailFactsText.when(date, now: now, calendar: calendar, locale: Locale(identifier: identifier))
                .replacingOccurrences(of: "\u{202F}", with: " ")
        }

        #expect(read("en_US") == "Nov 14, 2023, 10:13 PM")
        #expect(read("en_GB") == "14 Nov 2023, 22:13")
    }

    @Test("when it was copied is today, yesterday, or a date")
    func when_namesTodayAndYesterday() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(DetailFactsText.when(now, now: now, calendar: calendar).hasPrefix("Today, "))
        #expect(DetailFactsText.when(now.addingTimeInterval(-86_400), now: now, calendar: calendar)
            .hasPrefix("Yesterday, "))
        let older = DetailFactsText.when(now.addingTimeInterval(-86_400 * 9), now: now, calendar: calendar)
        #expect(!older.hasPrefix("Today") && !older.hasPrefix("Yesterday"))
    }

    @Test("the facts are one line joined with a middle dot")
    func line_joinsWithMiddleDots() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let line = DetailFactsText.line([.copied(now), .language("Python"), .lines(3)], now: now, calendar: calendar)

        #expect(line.hasSuffix(" · Python · 3 lines"))
    }
}
