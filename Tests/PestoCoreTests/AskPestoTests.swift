// SPDX-License-Identifier: MIT
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
}
