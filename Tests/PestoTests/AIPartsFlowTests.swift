// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import Testing
@testable import Pesto

private final class ModelLog: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []

    var all: [String] {
        lock.withLock { messages }
    }

    func add(_ message: String) {
        lock.withLock { messages.append(message) }
    }
}

@Suite("A long summary read a part at a time")
@MainActor
struct AIPartsFlowTests {
    private let long = (0..<60).map { "sentence number \($0)." }.joined(separator: " ")

    private func state(
        log: ModelLog = ModelLog(), failOn call: Int? = nil, hangOn hang: Int? = nil
    )
    -> AppState {
        let state = AppState()
        state.aiCoordinator = AIActionCoordinator(
            availability: { .available },
            complete: { _, message in
                log.add(message)
                let number = log.all.count
                if number == call { throw URLError(.cannotConnectToHost) }
                if number == hang { try await Task.sleep(for: .seconds(30)) }
                return "summary \(number)"
            },
            budget: { 100 }
        )
        return state
    }

    private func settle(_ state: AppState) async {
        for _ in 0..<200 {
            let reading = state.aiResult?.progress.map { $0.isReading || $0.isCombining } ?? false
            if !state.aiIsLoading, !reading { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("the first part is read at once and the rest wait for the person")
    func whenLongSummary_thenFirstPartOnly() async throws {
        let log = ModelLog()
        let state = state(log: log)

        state.runAIAction(.summarize, text: long)
        await settle(state)

        let progress = try #require(state.aiResult?.progress)
        #expect(progress.answers.count == 1 && progress.next?.index == 2)
        #expect(log.all.count == 1, "no part was read ahead of the click")
        #expect(state.aiRun != nil)
    }

    @Test("each click reads one more part, the last offers Combine, and Combine is one more call")
    func whenReadingOn_thenOneCallEach() async throws {
        let log = ModelLog()
        let state = state(log: log)
        state.runAIAction(.summarize, text: long)
        await settle(state)
        let parts = try #require(state.aiResult?.progress?.partCount)

        for read in 2...parts {
            state.readNextAIPart()
            await settle(state)
            #expect(log.all.count == read)
        }
        let done = try #require(state.aiResult?.progress)
        #expect(done.next == nil && !done.hasCombined)
        #expect(state.aiResult?.result.contains("summary 1") == true && state.aiResult?.result
            .contains("summary \(parts)") == true)

        state.combineAIParts()
        await settle(state)

        #expect(log.all.count == parts + 1)
        #expect(state.aiResult?.progress?.hasCombined == true)
        #expect(state.aiResult?.result == "summary \(parts + 1)")
    }

    @Test("a part that fails keeps the ones before it, and Try Again asks for the same part")
    func whenAPartFails_thenEarlierOnesStay() async throws {
        let state = state(failOn: 2)
        state.runAIAction(.summarize, text: long)
        await settle(state)

        state.readNextAIPart()
        await settle(state)

        var progress = try #require(state.aiResult?.progress)
        #expect(progress.answers.count == 1 && progress.failure != nil && progress.next?.index == 2)

        state.readNextAIPart()
        await settle(state)

        progress = try #require(state.aiResult?.progress)
        #expect(progress.answers.count == 2 && progress.failure == nil)
    }

    @Test("Cancel keeps the parts already read and ignores the call it ended")
    func whenCancelled_thenPartsKept() async throws {
        let state = state(hangOn: 2)
        state.runAIAction(.summarize, text: long)
        await settle(state)

        state.readNextAIPart()
        #expect(state.aiResult?.progress?.isReading == true)
        state.cancelAIPart()
        await settle(state)

        let progress = try #require(state.aiResult?.progress)
        #expect(!progress.isReading && progress.answers.count == 1 && progress.failure == nil)
    }

    @Test("closing the panel, or locking the history, drops the rest of the text")
    func whenCleared_thenRunDropped() async {
        let state = state()
        state.runAIAction(.summarize, text: long)
        await settle(state)
        #expect(state.aiRun != nil)

        state.aiResult = nil

        #expect(state.aiRun == nil)
    }

    @Test("a rewrite, a short text and the start of a bigger clip are one request, as before")
    func whenNotChunked_thenSingleResult() async {
        for run in [
            { (state: AppState) in state.runAIAction(.toneConcise, text: self.long) },
            { (state: AppState) in state.runAIAction(.summarize, text: "short") },
            { (state: AppState) in state.runAIAction(.summarize, text: self.long, totalCharacters: 9000) }
        ] {
            let state = state()
            run(state)
            await settle(state)
            #expect(state.aiResult?.progress == nil)
            #expect(state.aiRun == nil)
        }
    }
}
