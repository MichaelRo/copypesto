// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("A summary read one part at a time")
struct AIPartsRunTests {
    private struct Boom: Error, LocalizedError {
        var errorDescription: String? {
            "the model stopped"
        }
    }

    private func coordinator(
        budget: Int = 100, availability: AIAvailability = .available,
        completing: @escaping @Sendable (String, String) async throws -> String = { _, _ in "ok" }
    )
        -> AIActionCoordinator
    {
        AIActionCoordinator(availability: { availability }, complete: completing, budget: { budget })
    }

    private let long = (0..<60).map { "sentence number \($0)." }.joined(separator: " ")

    @Test("only a summary and key points are read in parts")
    func whenAction_thenOnlyContentActions() {
        #expect(AIAction.summarize.readsInParts && AIAction.keyPoints.readsInParts)
        #expect(!AIAction.toneProfessional.readsInParts && !AIAction.toneConcise.readsInParts)
        #expect(!AIAction.translate.readsInParts && !AIAction.extract.readsInParts && !AIAction.describeImage
            .readsInParts)
    }

    @Test("a long text has parts, a short one, a rewrite and a preview of a bigger clip have none")
    func whenParts_thenOnlyForALongSummary() {
        let engine = coordinator()
        #expect((engine.parts(action: .summarize, text: long)?.parts.count ?? 0) > 1)
        #expect(engine.parts(action: .keyPoints, text: long) != nil)
        #expect(engine.parts(action: .summarize, text: "short") == nil)
        #expect(engine.parts(action: .toneConcise, text: long) == nil)
        #expect(engine.parts(action: .summarize, text: long, totalCharacters: 50_000) == nil)
    }

    @Test("a part is one model call that sees that part and nothing else")
    func whenPart_thenOneCallWithOnlyIt() async {
        let calls = LockedBox<[String]>([])
        let engine = coordinator { _, message in
            calls.set(calls.get() + [message])
            return "answer"
        }
        let parts = engine.parts(action: .summarize, text: long)
        let second = parts?.parts[1]

        let outcome = await engine.summarizePart(action: .summarize, part: second ?? AIPart(text: "", start: 0, end: 0))

        #expect(outcome == .answer("answer"))
        #expect(calls.get().count == 1)
        #expect(calls.get()[0] == second?.text)
    }

    @Test("a failure, or no model, is an outcome with a reason, never a throw")
    func whenFails_thenFailureOutcome() async {
        let part = AIPart(text: "text", start: 1, end: 4)
        let broken = await coordinator { _, _ in throw Boom() }.summarizePart(action: .summarize, part: part)
        #expect(broken == .failure("the model stopped"))
        let off = await coordinator(availability: .unavailable(.turnedOff)).summarizePart(
            action: .summarize,
            part: part
        )
        #expect(off == .failure(AIAvailability.unavailable(.turnedOff).message))
    }

    @Test("combining is one call over the part summaries")
    func whenCombine_thenOneCallOverThem() async {
        let calls = LockedBox<[String]>([])
        let engine = coordinator { _, message in
            calls.set(calls.get() + [message])
            return "combined"
        }
        let outcome = await engine.combine(action: .summarize, answers: ["first answer", "second answer"])
        #expect(outcome == .answer("combined"))
        #expect(calls.get().count == 1)
        #expect(calls.get()[0].contains("first answer") && calls.get()[0].contains("second answer"))
    }

    @Test("a run knows its next part, what it has read, and when it is done")
    func whenRun_thenProgress() throws {
        let parts = try #require(coordinator().parts(action: .summarize, text: long))
        var run = AIRun(action: .summarize, parts: parts)
        #expect(run.nextIndex == 0 && run.next == parts.parts[0] && !run.isComplete)

        run.record("one")
        let progress = run.progress(isReading: false, isCombining: false, failure: nil)

        #expect(progress.answers.map(\.text) == ["one"])
        #expect(progress.answers.first?.index == 1)
        #expect(progress.partCount == parts.parts.count)
        #expect(progress.next?.index == 2)
        #expect(run.text == "one")

        for part in parts.parts.dropFirst() {
            run.record("more \(part.start)")
        }
        #expect(run.isComplete && run.next == nil)
        #expect(run.progress(isReading: false, isCombining: false, failure: nil).next == nil)
        #expect(run.text.contains("\n\n"))
    }

    @Test("a combined summary is what is pasted once there is one")
    func whenCombined_thenItIsTheText() throws {
        let parts = try #require(coordinator().parts(action: .summarize, text: long))
        var run = AIRun(action: .summarize, parts: parts)
        run.record("one")
        run.combined = "the whole of it"
        #expect(run.text == "the whole of it")
    }

    @Test("a clip cut at the ceiling says how much it read")
    func whenCeiling_thenCoverage() {
        let parts = AIChunker.parts(of: long, budget: 100, maxCharacters: 300)
        let run = AIRun(action: .summarize, parts: parts)
        let progress = run.progress(isReading: false, isCombining: false, failure: nil)
        #expect(progress.readableCharacters == 300 && progress.totalCharacters == long.count)
    }
}
