// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import SwiftData
import Testing
@testable import Pesto

private final class ThreadRecordingAuthenticator: UserAuthenticating, @unchecked Sendable {
    private let lock = NSLock()
    private var asked: [Bool] = []

    var askedOnMainThread: [Bool] {
        lock.withLock { asked }
    }

    func canAuthenticate() -> Bool {
        lock.withLock { asked.append(Thread.isMainThread) }
        return false
    }

    func authenticate(reason _: String) async -> Bool {
        false
    }
}

extension HostedGlobals {
    @Suite("History lock in the app", .serialized)
    @MainActor
    struct HistoryLockIntegrationTests {
        private let key = "biometricLockEnabled"

        @Test("turning the lock on locks history at the default timeout, without touching the picker")
        func lock_engagesAtTheDefault() {
            AppDefaults.store.set(true, forKey: key)
            defer { AppDefaults.store.removeObject(forKey: key) }
            let state = AppState()

            state.checkAndApplyBiometricLock()

            #expect(state.isHistoryLocked)
            #expect(state.isHistoryLockedNow())
        }

        @Test("turning the lock off and on again locks at once, even right after an unlock")
        func lock_reenabledAfterUnlock_locksImmediately() {
            AppDefaults.store.set(true, forKey: key)
            defer {
                AppDefaults.store.removeObject(forKey: key)
                AppDefaults.store.removeObject(forKey: HistoryLockPolicy.switchedOnKey)
            }
            let state = AppState()
            state.completeUnlock()
            #expect(!state.isHistoryLockedNow(), "unlocked for the session")

            HistoryLockPolicy.lockWasSwitchedOn(at: Date().addingTimeInterval(1))

            #expect(state.isHistoryLockedNow())
        }

        @Test("with the lock off, history is not locked")
        func lock_offMeansUnlocked() {
            AppDefaults.store.set(false, forKey: key)
            defer { AppDefaults.store.removeObject(forKey: key) }
            let state = AppState()

            #expect(!state.isHistoryLockedNow())
        }

        @Test("the default timeout is the setting's default, so it never reads back as zero")
        func timeout_isTheSettingsDefault() {
            #expect(AppDefaults.store.value(for: Setting.biometricLockTimeoutMinutes) == HistoryLockPolicy
                .defaultTimeoutMinutes)
        }

        @Test("locking clears the decrypted preview cache so plaintext does not outlive the lock")
        func lock_clearsDecryptedPreviews() {
            AppDefaults.store.set(true, forKey: key)
            defer { AppDefaults.store.removeObject(forKey: key) }
            let id = UUID()
            let nonce = Data(repeating: 9, count: 12)
            _ = PreviewTextCache.shared.text(id: id, nonce: nonce) { "plaintext" }
            var openedAgain = false
            let state = AppState()

            state.checkAndApplyBiometricLock()

            _ = PreviewTextCache.shared.text(id: id, nonce: nonce) {
                openedAgain = true
                return "plaintext"
            }
            #expect(openedAgain, "the cached plaintext survived the lock")
        }

        @Test("locking forgets the clipboard text kept for a snippet's placeholder (P-03)")
        func lock_forgetsTheClipboardKeptForASnippet() {
            AppDefaults.store.set(true, forKey: key)
            defer { AppDefaults.store.removeObject(forKey: key) }
            let state = AppState()
            state.clipboardBeforeLastItemWrite = "a copied secret"

            state.checkAndApplyBiometricLock()

            #expect(state.clipboardBeforeLastItemWrite.isEmpty)
        }

        @Test("locking forgets what could be undone and takes the Undo banner down (ADR 0008)")
        func lock_forgetsWhatCouldBeUndone() async throws {
            AppDefaults.store.set(true, forKey: key)
            defer { AppDefaults.store.removeObject(forKey: key) }
            let history = UndoHistory()
            let container = try ModelContainerSetup.makeInMemory().synced
            let service = StorageService(modelContainer: container, environment: .testing { $0.undoHistory = history })
            try await service.ingest(PasteboardCapture(
                typeIdentifier: "public.utf8-plain-text", payload: Data("a".utf8), payloadString: "a",
                timestamp: .now, contentHash: "hash-a"
            ))
            let ids = try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).map(\.id)
            let state = AppState()
            state.storageService = service
            let mark = history.recordedCount
            try await service.deleteItems(ids: ids, reason: .user)
            state.offerUndo(since: mark)
            #expect(state.undoOffer != nil)

            state.checkAndApplyBiometricLock()

            #expect(history.undoLabel == nil)
            #expect(state.undoOffer == nil)
            #expect(try await service.undo() == nil)
        }

        @Test("while the history is locked, ⌘Z and the Undo button restore nothing")
        func lock_refusesUndo() async throws {
            AppDefaults.store.set(true, forKey: key)
            defer { AppDefaults.store.removeObject(forKey: key) }
            let history = UndoHistory()
            let container = try ModelContainerSetup.makeInMemory().synced
            let service = StorageService(modelContainer: container, environment: .testing { $0.undoHistory = history })
            try await service.ingest(PasteboardCapture(
                typeIdentifier: "public.utf8-plain-text", payload: Data("a".utf8), payloadString: "a",
                timestamp: .now, contentHash: "hash-a"
            ))
            let state = AppState()
            state.storageService = service
            state.checkAndApplyBiometricLock()
            #expect(state.isHistoryLocked)
            let ids = try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).map(\.id)
            try await service.deleteItems(ids: ids, reason: .user)
            #expect(history.undoLabel != nil)

            state.performUndo()
            try await Task.sleep(for: .milliseconds(150))

            #expect(history.undoLabel == nil, "the locked history clears undo stack")
            #expect(try ModelContext(container).fetchCount(FetchDescriptor<ClipboardItem>()) == 0)
        }

        @Test("an unlocked history locks again when the idle timeout passes, without anyone opening a surface")
        func lock_engagesWhenIdleTimeoutPasses() {
            AppDefaults.store.set(true, forKey: key)
            defer {
                AppDefaults.store.removeObject(forKey: key)
                AppDefaults.store.removeObject(forKey: HistoryLockPolicy.switchedOnKey)
            }
            let state = AppState()
            state.completeUnlock(at: Date().addingTimeInterval(-3600))
            state.isHistoryLocked = false

            state.relockIfIdle()

            #expect(state.isHistoryLocked)
        }

        @Test("the availability check is a synchronous call to another process, so it never runs on the main thread")
        func availability_isAskedOffTheMainThread() async {
            let probe = ThreadRecordingAuthenticator()
            let state = AppState()

            await state.refreshAuthenticationAvailability(using: probe)

            #expect(probe.askedOnMainThread == [false])
            #expect(state.authenticationAvailability == .unavailable)
        }

        @Test("a history unlocked a moment ago stays unlocked when the timer checks")
        func lock_staysOpenInsideTheTimeout() {
            AppDefaults.store.set(true, forKey: key)
            defer {
                AppDefaults.store.removeObject(forKey: key)
                AppDefaults.store.removeObject(forKey: HistoryLockPolicy.switchedOnKey)
            }
            let state = AppState()
            state.completeUnlock()

            state.relockIfIdle()

            #expect(!state.isHistoryLocked)
        }

        @Test("a locked history refuses to put a clip on the pasteboard")
        func writeItem_whenLocked_writesNothing() {
            AppDefaults.store.set(true, forKey: key)
            defer { AppDefaults.store.removeObject(forKey: key) }
            let state = AppState()
            let item = ClipboardItem(
                type: .text, previewText: "an address", contentHash: "h", byteSize: 10, deviceID: "d", sequenceNumber: 1
            )
            let before = AppPasteboard.general.changeCount

            let kind = state.writeItem(item)

            #expect(kind == nil, "nothing is written, and nothing is pasted from what was on the board")
            #expect(AppPasteboard.general.changeCount == before)
        }
    }
}
