// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("Running an AI action on a clip")
@MainActor
struct MobileAITests {
    private func ready(_ library: MobileTestLibrary, budget: Int = 10_000) {
        library.state.aiAvailability = { .available }
        library.state.aiSupportsVision = { false }
        library.state.aiCoordinator = AIActionCoordinator(
            availability: { .available },
            complete: { system, message in "[\(system.prefix(12))] \(message.prefix(20))" },
            budget: { budget }
        )
    }

    private func finish(_ state: MobileAppState) async {
        while state.aiIsLoading {
            await Task.yield()
        }
    }

    @Test("an action runs on the clip's whole text, and its answer waits in the sheet")
    func whenAnActionRuns_thenTheAnswerIsPresented() async throws {
        let library = try await MobileTestLibrary()
        ready(library)
        let note = try await library.add("A long note about basil and pine nuts")

        library.state.runAIAction(.summarize, on: note)
        #expect(library.state.showsAI)
        await finish(library.state)

        let result = try #require(library.state.aiResult)
        #expect(result.action == .summarize)
        #expect(!result.isError)
        #expect(result.result.contains("A long note about"))
        #expect(result.coverage?.isPartial == false)
    }

    @Test("a text longer than the model's budget says how much of it was read")
    func whenTheTextIsTooLong_thenTheAnswerSaysSo() async throws {
        let library = try await MobileTestLibrary()
        ready(library, budget: 20)
        let note = try await library.add(String(repeating: "word ", count: 40))

        library.state.runAIAction(.keyPoints, on: note)
        await finish(library.state)

        let result = try #require(library.state.aiResult)
        #expect(result.coverage?.isPartial == true)
        #expect(result.coverage?.note.hasPrefix("Based on the first") == true)
    }

    @Test("nothing runs for a secret, with the model off, or for an action the clip does not offer")
    func whenNotOffered_thenNothingRuns() async throws {
        let library = try await MobileTestLibrary()
        ready(library)
        try await library.service.ingest(#require(ClipCapture.text("ghp_8fK2mQ9xLr4TzW7nB1vC6yH3sJ5dE0aGpU2i")))
        let secret = try await library.settle()
        library.state.runAIAction(.summarize, on: secret)
        #expect(!library.state.showsAI)

        let note = try await library.add("an ordinary note")
        library.state.runAIAction(.describeImage, on: note)
        #expect(!library.state.showsAI)

        library.state.aiAvailability = { .unavailable(.turnedOff) }
        library.state.runAIAction(.summarize, on: note)
        #expect(!library.state.showsAI)
        #expect(library.state.aiOffer(for: note).reason == AIAvailability.unavailable(.turnedOff).message)
    }

    @Test("a failure is the answer, as an error, and Copy is not offered for it")
    func whenTheModelFails_thenTheErrorIsShown() async throws {
        let library = try await MobileTestLibrary()
        ready(library)
        library.state.aiCoordinator = AIActionCoordinator(
            availability: { .available }, complete: { _, _ in throw AppleIntelligenceClient.ClientError.tooLong },
            budget: { 100 }
        )
        let note = try await library.add("some text")

        library.state.runAIAction(.translate, on: note)
        await finish(library.state)

        let result = try #require(library.state.aiResult)
        #expect(result.isError)
        #expect(!result.canPaste)
        #expect(await !library.state.copyAIResult())
    }

    @Test("Copy puts the answer on the clipboard and keeps it as a clip; Done and the lock drop the answer")
    func whenCopiedOrClosed_thenTheAnswerIsKeptOrDropped() async throws {
        let library = try await MobileTestLibrary()
        ready(library)
        let note = try await library.add("text to rewrite")
        library.state.runAIAction(.toneConcise, on: note)
        await finish(library.state)
        let answer = try #require(library.state.aiResult?.result)

        #expect(await library.state.copyAIResult())
        #expect(AppPasteboard.general.string == answer)
        try await library.refreshed()
        #expect(library.store.items.contains { $0.displayPreviewText == answer })

        library.state.closeAI()
        #expect(library.state.aiResult == nil)
        #expect(!library.state.showsAI)
        #expect(!library.state.aiIsLoading)
    }
}
