// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("A secret written from a stack leaves the pasteboard", .serialized)
    @MainActor
    final class StackSecretClearTests {
        private let state = AppState()

        init() {
            state.secretClearDelay = .milliseconds(50)
            AppPasteboard.general.clearContents()
        }

        deinit {
            AppDefaults.store.set(false, forKey: "biometricLockEnabled")
        }

        private func secret(_ text: String) -> PasteStack.Item {
            PasteStack.Item(
                previewText: text, payloadKind: .text(text),
                pasteboardData: Data(text.utf8), pasteboardType: "public.utf8-plain-text", isProtected: true
            )
        }

        private func ordinary(_ text: String) -> PasteStack.Item {
            PasteStack.Item(previewText: text, payloadKind: .text(text))
        }

        private var boardTypes: [String] {
            (AppPasteboard.general.types ?? []).map(\.rawValue)
        }

        @Test("a secret written from a stack is marked concealed")
        func whenAStackWritesASecret_thenItIsMarked() {
            state.writeStackItem(secret("4242 4242 4242 4242"))

            #expect(PasteboardProtection.isProtected(types: boardTypes))
            #expect(AppPasteboard.general.string(forType: .string) == "4242 4242 4242 4242")
        }

        @Test("a secret written from a stack is cleared after the delay if nothing else was copied")
        func whenAStackWritesASecret_thenItIsClearedAfterTheDelay() async throws {
            state.writeStackItem(secret("4242 4242 4242 4242"))
            #expect(AppPasteboard.general.string(forType: .string) != nil)

            try await Task.sleep(for: .milliseconds(400))

            #expect(AppPasteboard.general.string(forType: .string) == nil)
        }

        @Test("a secret written from a stack is left alone if something else was copied meanwhile")
        func whenSomethingElseIsCopied_thenTheStackSecretClearDoesNothing() async throws {
            state.secretClearDelay = .milliseconds(150)
            state.writeStackItem(secret("4242 4242 4242 4242"))
            AppPasteboard.general.clearContents()
            AppPasteboard.general.setString("a newer copy", forType: .string)

            try await Task.sleep(for: .milliseconds(500))

            #expect(AppPasteboard.general.string(forType: .string) == "a newer copy")
        }

        @Test("the last secret of a stack is cleared, however many clips came before it")
        func whenAStackEndsOnASecret_thenTheLastOneIsCleared() async throws {
            var stack = PasteStack(items: [ordinary("first"), secret("hunter2"), secret("4242 4242 4242 4242")])
            while let item = stack.current {
                state.writeStackItem(item)
                stack.advance()
            }
            #expect(AppPasteboard.general.string(forType: .string) == "4242 4242 4242 4242")

            try await Task.sleep(for: .milliseconds(400))

            #expect(AppPasteboard.general.string(forType: .string) == nil)
        }

        @Test("an ordinary clip written from a stack stays on the pasteboard")
        func whenAStackWritesAnOrdinaryClip_thenItIsNotCleared() async throws {
            state.writeStackItem(ordinary("quarterly numbers for the team"))

            try await Task.sleep(for: .milliseconds(400))

            #expect(AppPasteboard.general.string(forType: .string) == "quarterly numbers for the team")
            #expect(!PasteboardProtection.isProtected(types: boardTypes))
        }

        @Test("an ordinary clip after a secret is not cleared by the secret's timer")
        func whenAnOrdinaryClipFollowsASecret_thenItStays() async throws {
            state.writeStackItem(secret("hunter2"))
            state.writeStackItem(ordinary("lunch at noon"))

            try await Task.sleep(for: .milliseconds(400))

            #expect(AppPasteboard.general.string(forType: .string) == "lunch at noon")
        }

        @Test("with the history locked, a stack writes nothing")
        func whenLocked_thenAStackWritesNothing() {
            AppDefaults.store.set(true, forKey: "biometricLockEnabled")
            AppPasteboard.general.setString("what was copied before", forType: .string)

            state.writeStackItem(secret("hunter2"))

            #expect(AppPasteboard.general.string(forType: .string) == "what was copied before")
        }

        @Test("when a stack secret times out, the active stack is cancelled")
        func whenStackSecretTimesOut_thenActiveStackIsCancelled() async throws {
            var cancelled = false
            state.cancelActiveStack = { cancelled = true }
            state.activeStack = PasteStack(items: [secret("hunter2"), ordinary("next")])
            state.writeStackItem(secret("hunter2"))

            try await Task.sleep(for: .milliseconds(400))

            #expect(cancelled)
            #expect(AppPasteboard.general.string(forType: .string) == nil)
        }
    }
}
