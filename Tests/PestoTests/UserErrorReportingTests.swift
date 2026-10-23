// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import Pesto

private struct StoreFailure: Error {}

@Suite("User-visible errors")
@MainActor
struct UserErrorReportingTests {
    @Test("a failing action sets lastUserError with the action's wording")
    func whenActionThrows_thenLastUserErrorNamesTheAction() {
        let state = AppState()

        state.attempt("Couldn't save the change") { throw StoreFailure() }

        #expect(state.lastUserError == "Couldn't save the change")
    }

    @Test("a succeeding action leaves lastUserError alone")
    func whenActionSucceeds_thenNoError() {
        let state = AppState()

        state.attempt("Couldn't save the change") {}

        #expect(state.lastUserError == nil)
    }

    @Test("an async failing action is reported too")
    func whenAsyncActionThrows_thenReported() {
        let state = AppState()

        state.attempt("Couldn't delete the item") { throw StoreFailure() }

        #expect(state.lastUserError == "Couldn't delete the item")
    }

    @Test("dismissing clears the error")
    func whenDismissed_thenCleared() {
        let state = AppState()
        state.attempt("x") { throw StoreFailure() }

        state.dismissUserError()

        #expect(state.lastUserError == nil)
    }

    @Test("a message stays for at least ten seconds by default, and twenty with VoiceOver")
    func whenDefaultDuration_thenLongEnoughToRead() {
        #expect(AppState.defaultUserMessageDuration >= .seconds(10))
    }

    @Test("a message does not go while the pointer is on it, and goes shortly after the pointer leaves")
    func whenHovered_thenHeldThenReleased() async throws {
        let state = AppState()
        state.showUserMessage("Couldn\u{2019}t save the shortcut", lasting: .milliseconds(60))

        state.holdUserError()
        try await Task.sleep(for: .milliseconds(200))
        #expect(state.lastUserError != nil, "the banner went while it was being read")

        state.releaseUserError(after: .milliseconds(60))
        try await Task.sleep(for: .milliseconds(250))
        #expect(state.lastUserError == nil)
    }
}
