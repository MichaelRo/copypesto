// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("The app's lifecycle: what the lock forgets, what a failed save says, and when the foreground work runs")
@MainActor
struct MobileLifecycleTests {
    private struct Failure: Error {}

    private struct FailingRetentionStore: RetentionStore {
        func retentionSnapshot(expiringBefore _: Date) async throws -> RetentionSnapshot {
            throw Failure()
        }

        func deleteItems(ids _: [UUID]) async throws {}
    }

    private func lockCapable() -> MobileHistoryLock {
        MobileHistoryLock(
            authenticator: StubUserAuthenticator(available: true, grants: true), grace: AuthenticationGrace(),
            isEnabled: { true }
        )
    }

    @Test("locking forgets a snippet's fill sheet and a widget link already opened")
    func whenLocked_thenPendingFillAndLinkAreGone() async throws {
        let library = try await MobileTestLibrary(lock: lockCapable())
        await library.state.unlockHistory()
        let item = try await library.add("Dear {{input:Name}}")
        _ = try await library.service.togglePinned(id: item.id)
        try await library.refreshed()
        let snippet = try #require(library.store.item(for: item.id))
        #expect(!library.state.copy(snippet))
        #expect(library.state.pendingFill != nil)
        library.state.linkedClip = .init(id: item.id, opensDetail: true, serial: 1)

        library.state.lockHistory()

        #expect(library.state.pendingFill == nil)
        #expect(library.state.linkedClip == nil)
    }

    @Test("a copy whose save fails keeps the error on screen instead of saying Copied")
    func whenSaveFails_thenTheErrorStays() async throws {
        let library = try await MobileTestLibrary()
        let item = try await library.add("copy me")
        library.state.saveChanges = { _ in throw Failure() }

        _ = library.state.copy(item)

        #expect(library.state.notice?.isProblem == true)
        #expect(library.state.notice?.text != "Copied")
    }

    @Test("a copy that saves says Copied")
    func whenSaveSucceeds_thenCopied() async throws {
        let library = try await MobileTestLibrary()
        let item = try await library.add("copy me too")

        _ = library.state.copy(item)

        #expect(library.state.notice == .init(text: "Copied", isProblem: false))
    }

    @Test("Add to Pesto refuses while the history is locked, as Add Clipboard does")
    func whenLocked_thenAddFromShortcutRefuses() async throws {
        let library = try await MobileTestLibrary(lock: lockCapable())

        await #expect(throws: MobileAppState.ShortcutFailure.locked) {
            try await library.state.addFromShortcut(text: "while locked", file: nil, fileType: nil)
        }
        #expect(!library.store.items.contains { $0.displayPreviewText == "while locked" })
    }

    @Test("the foreground work runs once at launch and once for each return from the background")
    func whenActivatedRepeatedly_thenOncePerForeground() async throws {
        let library = try await MobileTestLibrary()

        await library.state.activate()
        await library.state.activate()
        #expect(library.state.activationCount == 1)

        library.state.didLeaveForeground()
        await library.state.activate()
        await library.state.activate()
        #expect(library.state.activationCount == 2)
    }

    @Test("a failed retention sweep is not recorded, so the next return tries again")
    func whenSweepFails_thenItIsRetried() async throws {
        let library = try await MobileTestLibrary()
        library.state.retentionPolicy = { RetentionPolicy.chosen(days: 30, maxItems: 5000) }
        library.state.retentionSchedule = RetentionSchedule()
        library.state.retentionStore = { _ in FailingRetentionStore() }

        await library.state.pruneHistory()
        #expect(library.state.retentionSchedule.lastSweep == nil)

        library.state.retentionStore = { StorageRetentionStore(service: $0) }
        await library.state.pruneHistory()
        #expect(library.state.retentionSchedule.lastSweep != nil)
    }
}
