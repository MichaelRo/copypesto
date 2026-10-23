// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("AIActionCoordinator")
struct AIActionCoordinatorTests {
    private struct Boom: Error, LocalizedError {
        var errorDescription: String? {
            "model said no"
        }
    }

    private func coordinator(
        availability: AIAvailability = .available,
        completing: @escaping @Sendable (String, String) async throws -> String
    )
    -> AIActionCoordinator {
        AIActionCoordinator(availability: { availability }, complete: completing)
    }

    @Test("a text action returns the model's answer")
    func whenModelAnswers_thenResult() async {
        let result = await coordinator { _, _ in "Short summary." }.run(action: .summarize, text: "Long text")
        #expect(!result.isError)
        #expect(result.result == "Short summary.")
        #expect(result.action == .summarize)
    }

    @Test("the action's own prompt and the clip text are what the model receives")
    func whenRun_thenModelGetsPromptAndText() async {
        let seen = LockedBox<[String]>([])
        _ = await coordinator { system, message in
            seen.set([system, message])
            return "ok"
        }.run(action: .translate, text: "Hola mundo")
        #expect(seen.get()[0] == AIAction.translate.systemPrompt)
        #expect(seen.get()[1].contains("Hola mundo"))
    }

    @Test("when the model is missing, nothing is sent and the result says why")
    func whenUnavailable_thenErrorWithReason() async {
        let called = LockedBox(false)
        let result = await coordinator(availability: .unavailable(.notEnabled)) { _, _ in
            called.set(true)
            return "x"
        }.run(action: .summarize, text: "text")
        #expect(result.isError)
        #expect(result.result == AIAvailability.unavailable(.notEnabled).message)
        #expect(!called.get())
    }

    @Test("a failing model becomes an error result, never a throw")
    func whenModelThrows_thenErrorResult() async {
        let result = await coordinator { _, _ in throw Boom() }.run(action: .summarize, text: "text")
        #expect(result.isError)
        #expect(result.result == "model said no")
    }

    @Test("the source preview is cut at 80 characters and flattened to one line")
    func whenLongText_thenPreviewTruncated() async {
        let long = "line one\n" + String(repeating: "a", count: 200)
        let result = await coordinator { _, _ in "ok" }.run(action: .summarize, text: long)
        #expect(result.sourcePreview.count <= 80)
        #expect(!result.sourcePreview.contains("\n"))
    }

    @Test("a clip longer than the budget reaches the model cut at the budget, and the answer says how much was read")
    func whenTextIsLong_thenModelGetsTheBudgetAndResultIsPartial() async {
        let seen = LockedBox("")
        let coordinator = AIActionCoordinator(
            availability: { .available }, complete: { _, message in seen.set(message)
                return "ok"
            }, budget: { 1000 }
        )

        let result = await coordinator.run(action: .summarize, text: String(repeating: "word ", count: 600))

        #expect(seen.get().count <= 1000)
        #expect(!seen.get().contains("truncated"))
        #expect(result.coverage?.isPartial == true)
        #expect(result.coverage?.total == 3000)
    }

    @Test("a clip inside the budget is read whole")
    func whenTextIsShort_thenWhole() async {
        let result = await coordinator { _, _ in "ok" }.run(action: .summarize, text: "A short note")

        #expect(result.coverage == AIResult.Coverage(shown: 12, total: 12))
        #expect(result.coverage?.isPartial == false)
    }

    @Test("text that is only the start of a longer clip is reported as partial")
    func whenOnlyAPreviewIsGiven_thenPartial() async {
        let result = await coordinator { _, _ in "ok" }
            .run(action: .summarize, text: "The first 500", totalCharacters: 90_000)

        #expect(result.coverage == AIResult.Coverage(shown: 13, total: 90_000))
    }

    @Test("a text the model cannot hold becomes a plain sentence, not a framework message")
    func whenTooLong_thenPlainSentence() {
        #expect(AppleIntelligenceClient.ClientError.tooLong.errorDescription?.contains("too long") == true)
    }

    @Test("every action has a symbol and a prompt")
    func allActions_haveSymbolsAndPrompts() {
        for action in AIAction.allCases {
            #expect(!action.symbolName.isEmpty)
            #expect(!action.systemPrompt.isEmpty)
        }
    }

    @Test("Describe Image honours the person's switch like every other AI action")
    func describeImage_whenTurnedOff_isRefusedWithTheRealReason() async {
        let coordinator = AIActionCoordinator(availability: { .unavailable(.turnedOff) }, complete: { _, _ in "x" })

        let result = await coordinator.describeImage(Data([1, 2, 3]))

        #expect(result.isError)
        #expect(result.result == AIAvailability.unavailable(.turnedOff).message)
    }

    @Test("the client says it is turned off, not that macOS is too old")
    func clientError_whenTurnedOff_saysSo() {
        #expect(AppleIntelligenceClient.ClientError.turnedOff.errorDescription?.contains("Turned off") == true)
    }
}

final class LockedBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func get() -> Value {
        lock.withLock { value }
    }

    func set(_ new: Value) {
        lock.withLock { value = new }
    }
}
