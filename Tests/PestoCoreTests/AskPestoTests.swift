// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Ask Pesto")
struct AskPestoTests {
    private let rules = RuleBasedQueryInterpreter()

    @Test("a plain word stays a keyword search")
    func whenPlainWord_thenKeywordOnly() {
        let query = rules.interpret("invoice")
        #expect(query == AskPestoQuery(keywords: "invoice", types: [], range: .all))
    }

    @Test("filler words drop out and a type word becomes a type filter")
    func whenSentence_thenKeywordsTypeAndRange() {
        let query = rules.interpret("the invoice link I copied last week")
        #expect(query.keywords == "invoice")
        #expect(query.types == [.url])
        #expect(query.range == .week)
    }

    @Test("date phrases map to the ranges the filter bar has, including yesterday and relative day counts")
    func whenDatePhrase_thenRange() {
        #expect(rules.interpret("password today").range == .today)
        #expect(rules.interpret("code from this morning").range == .today)
        #expect(rules.interpret("report yesterday").range == .yesterday)
        #expect(rules.interpret("links from last night").range == .yesterday)
        #expect(rules.interpret("notes from 3 days ago").range == .week)
        #expect(rules.interpret("files from a few days ago").range == .week)
        #expect(rules.interpret("report this month").range == .month)
        #expect(rules.interpret("report last month").range == .month)
        #expect(rules.interpret("links from last 14 days").range == .month)
    }

    @Test("text and slash-separated type words are recognised as type filters and removed from keywords")
    func whenTextOrPicturesFromYesterday_thenTypesAndYesterdayFilterWithoutKeywords() {
        let textQuery = rules.interpret("text from yesterday")
        #expect(textQuery == AskPestoQuery(keywords: "", types: [.text], range: .yesterday))

        let picQuery = rules.interpret("pictures from yesterday")
        #expect(picQuery == AskPestoQuery(keywords: "", types: [.image], range: .yesterday))

        let slashQuery = rules.interpret("text/pictures from yesterday")
        #expect(slashQuery == AskPestoQuery(keywords: "", types: [.text, .image], range: .yesterday))
    }

    @Test("several type words are all kept, once each")
    func whenSeveralTypeWords_thenAllKept() {
        let query = rules.interpret("screenshot or picture or code")
        #expect(query.types == [.image, .code])
        #expect(query.keywords.isEmpty)
    }

    @Test("a question that is only filters leaves the keywords empty")
    func whenOnlyFilters_thenNoKeywords() {
        let query = rules.interpret("images from today")
        #expect(query == AskPestoQuery(keywords: "", types: [.image], range: .today))
    }

    @Test("names and numbers are never dropped")
    func whenProperNounsAndNumbers_thenKept() {
        #expect(rules.interpret("the link from Anna about 2027 budget").keywords == "Anna 2027 budget")
    }

    @Test("a query with no filters says so, and one with filters lists them")
    func whenSummarised_thenReadable() {
        #expect(AskPestoQuery(keywords: "x", types: [], range: .all).hasFilters == false)
        let query = AskPestoQuery(keywords: "invoice", types: [.url], range: .week)
        #expect(query.hasFilters)
        #expect(query.summary == "Links · past 7 days · \u{201C}invoice\u{201D}")
        let yesterdayQuery = AskPestoQuery(keywords: "", types: [.text], range: .yesterday)
        #expect(yesterdayQuery.summary == "Text · yesterday")
    }

    @Test("with no model the interpreter falls back to the rules")
    func whenModelFails_thenRulesAnswer() async {
        struct Failing: QueryInterpreting {
            func interpret(_: String) async throws -> AskPestoQuery {
                throw CancellationError()
            }
        }
        let interpreter = FallbackQueryInterpreter(primary: Failing(), fallback: rules)
        let query = await interpreter.interpret("invoice link today")
        #expect(query.types == [.url] && query.range == .today && query.keywords == "invoice")
    }

    @Test("the model's answer wins when it works, and deterministic date and type words override hallucinations")
    func whenModelWorks_thenItsAnswerIsUsedAndReconciled() async {
        struct Fixed: QueryInterpreting {
            func interpret(_: String) async throws -> AskPestoQuery {
                AskPestoQuery(keywords: "  budget ", types: [.file], range: .month)
            }
        }
        let interpreter = FallbackQueryInterpreter(primary: Fixed(), fallback: rules)
        let query = await interpreter.interpret("anything")
        #expect(query == AskPestoQuery(keywords: "budget", types: [.file], range: .month))

        struct MisleadingModel: QueryInterpreting {
            func interpret(_: String) async throws -> AskPestoQuery {
                AskPestoQuery(keywords: "text yesterday", types: [], range: .today)
            }
        }
        let reconciled = await FallbackQueryInterpreter(primary: MisleadingModel(), fallback: rules)
            .interpret("text from yesterday")
        #expect(reconciled == AskPestoQuery(keywords: "", types: [.text], range: .yesterday))
    }

    @Test("the real on-device model understands a question", .enabled(if: Self.modelAvailable))
    func whenModelAvailable_thenParsesQuestion() async throws {
        guard #available(macOS 26, *) else { return }
        let query = try await OnDeviceQueryInterpreter().interpret("the invoice link from last week")
        #expect(query.types.contains(.url))
        #expect(query.range == .week)
    }

    static var modelAvailable: Bool {
        OnDeviceQueryInterpreter.isAvailable
    }

    // MARK: Dates beyond the five presets

    /// Thursday 5 November 2026, noon.
    private var now: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12)) ?? .distantPast
    }

    private func day(_ month: Int, _ day: Int, year: Int = 2026) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    private func ask(_ question: String) -> AskPestoQuery {
        rules.interpret(question, now: now)
    }

    @Test("the last N hours or minutes is a range that ends now")
    func whenHoursOrMinutes_thenRelativeRange() {
        #expect(ask("invoice last 3 hours") == AskPestoQuery(
            keywords: "invoice", types: [],
            range: .last(3 * 3600)
        ))
        #expect(ask("links 30 minutes ago").range == .last(1800))
        #expect(ask("code last hour").range == .last(3600))
        #expect(ask("report an hour ago").range == .last(3600))
    }

    @Test("a named day is that calendar day, in either order and with an ordinal")
    func whenNamedDay_thenThatDay() {
        let nov3 = DateInterval(start: day(11, 3), end: day(11, 4))
        #expect(ask("invoice on Nov 3") == AskPestoQuery(keywords: "invoice", types: [], range: .custom(nov3)))
        #expect(ask("notes on November 3rd").range == .custom(nov3))
        #expect(ask("notes 3 Nov").range == .custom(nov3))
        #expect(ask("notes on 2026-11-03").range == .custom(nov3))
    }

    @Test("a day later in the year than today means last year")
    func whenDayIsInTheFuture_thenLastYear() {
        #expect(ask("cards on Dec 25").range == .custom(DateInterval(
            start: day(12, 25, year: 2025),
            end: day(12, 26, year: 2025)
        )))
    }

    @Test("a weekday is its most recent past occurrence")
    func whenWeekday_thenMostRecentPast() {
        #expect(ask("notes on Monday").range == .custom(DateInterval(start: day(11, 2), end: day(11, 3))))
        #expect(ask("notes last Thursday").range == .custom(DateInterval(start: day(10, 29), end: day(10, 30))))
    }

    @Test("between two days covers both, to the end of the second")
    func whenBetweenTwoDays_thenRange() {
        let expected = AskDateRange.custom(DateInterval(start: day(11, 1), end: day(11, 4)))
        #expect(ask("between Nov 1 and Nov 3").range == expected)
        #expect(ask("report from Nov 1 to Nov 3") == AskPestoQuery(keywords: "report", types: [], range: expected))
    }

    @Test("a word that is only sometimes a date stays a keyword")
    func whenMonthNameAloneOrNoDay_thenKeyword() {
        #expect(ask("may budget").keywords == "may budget")
        #expect(ask("monday standup").keywords == "monday standup")
        #expect(ask("from Anna").keywords == "Anna")
        #expect(ask("from Anna").range == .all)
    }

    @Test("idioms that only look like a time stay keywords")
    func whenIdiom_thenKeyword() {
        #expect(ask("last minute deal").range == .all)
        #expect(ask("last minute deal").keywords == "minute deal")
        #expect(ask("three hours of video").range == .last(3 * 3600))
    }

    @Test("the presets are unchanged")
    func whenPreset_thenUnchanged() {
        #expect(ask("report last week").range == .week)
        #expect(ask("links from last 14 days").range == .month)
        #expect(ask("password today").range == .today)
    }

    @Test("a custom range is described the way a person says it")
    func whenCustomRange_thenReadableSummary() {
        #expect(AskDateRange.last(3 * 3600).label(now: now) == "Last 3 hours")
        #expect(AskDateRange.last(1800).label(now: now) == "Last 30 minutes")
        #expect(AskDateRange.last(3600).label(now: now) == "Last hour")
        let en = Locale(identifier: "en_US")
        let nov3 = AskDateRange.custom(DateInterval(start: day(11, 3), end: day(11, 4)))
        #expect(nov3.label(now: now, locale: en) == "Nov 3")
        let nov1to3 = AskDateRange.custom(DateInterval(start: day(11, 1), end: day(11, 4)))
        #expect(nov1to3.label(now: now, locale: en) == "Nov 1 \u{2013} Nov 3")
        let lastYear = AskDateRange.custom(DateInterval(start: day(12, 25, year: 2025), end: day(12, 26, year: 2025)))
        #expect(lastYear.label(now: now, locale: en) == "Dec 25, 2025")
        #expect(AskDateRange.last(90 * 60).label(now: now) == "Last 90 minutes")
        #expect(AskDateRange.week.label(now: now) == "Last 7 days")
        #expect(AskDateRange.all.label(now: now) == "Any time")
    }

    @Test("a dash joins two days, and a range written backwards still covers both")
    func whenDashOrBackwards_thenSameRange() {
        let expected = AskDateRange.custom(DateInterval(start: day(11, 1), end: day(11, 4)))
        #expect(ask("report Nov 1 - Nov 3").range == expected)
        #expect(ask("from Nov 3 to Nov 1").range == expected)
    }

    @Test("a day is 23 hours long when the clocks go forward, so it still ends at the next midnight")
    func whenDaylightSavingDay_thenEndsAtNextMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let noon = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12)))
        let query = rules.interpret("invoice on Mar 8", now: noon, calendar: calendar)

        guard case let .custom(range) = query.range else {
            Issue.record("not a custom range")
            return
        }
        #expect(range.duration == 23 * 3600)
    }
}
