// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftData
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("Paste from Pesto respects the lock and the masking", .serialized)
    @MainActor
    final class PasteIntentLockTests {
        private let state = AppState()
        private let service: StorageService

        init() async throws {
            let container = try ModelContainerSetup.makeInMemory().synced
            state.historyContainer = container
            service = StorageService(modelContainer: container)
            ScriptingContext.appState = state
            AppDefaults.store.set(false, forKey: "biometricLockEnabled")
            AppPasteboard.general.clearContents()
        }

        isolated deinit {
            ScriptingContext.appState = nil
            AppDefaults.store.set(false, forKey: "biometricLockEnabled")
        }

        private func ingest(_ text: String) async throws {
            try await service.ingest(PasteboardCapture(
                typeIdentifier: "public.utf8-plain-text",
                payload: Data(text.utf8),
                payloadString: text,
                contentHash: UUID().uuidString
            ))
        }

        private func run(_ search: String) async throws -> String {
            let intent = PasteFromPestoIntent()
            intent.search = search
            return try await intent.perform().value ?? ""
        }

        @Test("with the lock on, the intent hands out nothing and leaves the pasteboard alone")
        func whenLocked_thenRefused() async throws {
            try await ingest("quarterly numbers for the team")
            AppDefaults.store.set(true, forKey: "biometricLockEnabled")
            defer { AppDefaults.store.set(false, forKey: "biometricLockEnabled") }

            await #expect(throws: (any Error).self) { _ = try await run("quarterly") }
            #expect(AppPasteboard.general.string(forType: .string) == nil)
        }

        @Test("a clip containing a secret is never returned, even when searched by its digits")
        func whenSecret_thenNotReturned() async throws {
            try await ingest("4242 4242 4242 4242")

            await #expect(throws: (any Error).self) { _ = try await run("4242") }
            #expect(AppPasteboard.general.string(forType: .string) == nil, "the card number must not reach the board")
        }

        @Test("a clip whose saved data will not open pastes nothing, says so, and leaves the pasteboard alone")
        func whenTheBlobWillNotOpen_thenRefusedAndReported() async throws {
            try await ingest("quarterly numbers for the team")
            let container = try #require(state.historyContainer)
            let context = ModelContext(container)
            let item = try #require(context.fetch(FetchDescriptor<ClipboardItem>()).first)
            let blob = try #require(item.blob)
            var bytes = Data(blob.encryptedData)
            bytes[0] ^= 0xFF
            blob.encryptedData = bytes
            try context.save()
            AppPasteboard.general.clearContents()
            AppPasteboard.general.setString("what was copied before", forType: .string)

            let payload = state.writeItem(item)

            #expect(payload == nil, "the 500-character preview must not stand in for the clip")
            #expect(AppPasteboard.general.string(forType: .string) == "what was copied before")
            #expect(state.lastUserError != nil)
        }

        private func secretItem() async throws -> ClipboardItem {
            try await ingest("4242 4242 4242 4242")
            let container = try #require(state.historyContainer)
            return try #require(ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first)
        }

        @Test("a pasted secret is taken off the pasteboard after a while if nothing else was copied")
        func whenASecretIsPasted_thenItIsClearedAfterTheDelay() async throws {
            state.secretClearDelay = .milliseconds(50)
            let item = try await secretItem()

            _ = state.writeItem(item)
            #expect(AppPasteboard.general.string(forType: .string) != nil)
            try await Task.sleep(for: .milliseconds(400))

            #expect(AppPasteboard.general.string(forType: .string) == nil)
        }

        @Test("if something else is copied in the meantime, the pasteboard is left alone")
        func whenSomethingElseIsCopied_thenTheSecretClearDoesNothing() async throws {
            state.secretClearDelay = .milliseconds(150)
            let item = try await secretItem()

            _ = state.writeItem(item)
            AppPasteboard.general.clearContents()
            AppPasteboard.general.setString("a newer copy", forType: .string)
            try await Task.sleep(for: .milliseconds(500))

            #expect(AppPasteboard.general.string(forType: .string) == "a newer copy")
        }

        @Test("an ordinary clip stays on the pasteboard")
        func whenAnOrdinaryClipIsPasted_thenItIsNotCleared() async throws {
            state.secretClearDelay = .milliseconds(50)
            try await ingest("quarterly numbers for the team")
            let container = try #require(state.historyContainer)
            let item = try #require(ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first)

            _ = state.writeItem(item)
            try await Task.sleep(for: .milliseconds(400))

            #expect(AppPasteboard.general.string(forType: .string) == "quarterly numbers for the team")
        }

        @Test("an ordinary clip still works when unlocked")
        func whenUnlocked_thenOrdinaryClipReturned() async throws {
            try await ingest("quarterly numbers for the team")

            let result = try await run("quarterly")

            #expect(result == "quarterly numbers for the team")
        }
    }
}
