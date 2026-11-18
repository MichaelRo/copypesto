// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("The History Lock on iPhone and iPad locks like the Mac's", .serialized)
@MainActor
struct MobileHistoryLockTests {
    private let secret = "ghp_8fK2mQ9xLr4TzW7nB1vC6yH3sJ5dE0aGpU2i"

    final class LockSetting {
        var isOn: Bool
        var minutes = 5
        var showsOutside = false

        init(_ isOn: Bool) {
            self.isOn = isOn
        }
    }

    private func lock(
        _ setting: LockSetting, available: Bool = true, grants: Bool = true
    )
    -> MobileHistoryLock {
        MobileHistoryLock(
            authenticator: StubUserAuthenticator(available: available, grants: grants), grace: AuthenticationGrace(),
            isEnabled: { setting.isOn }, timeoutMinutes: { setting.minutes },
            showsClipsOutside: { setting.showsOutside }
        )
    }

    private func library(
        _ setting: LockSetting, time: TimeBox = TimeBox(), available: Bool = true, grants: Bool = true
    ) async throws
    -> MobileTestLibrary {
        try await MobileTestLibrary(
            lock: lock(setting, available: available, grants: grants), clock: { time.now }
        )
    }

    private func temporaryFolder(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-mobile-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test("the lock is off by default, as on the Mac, and an unlocked launch opens the library")
    func whenOff_thenNothingIsLocked() async throws {
        #expect(Setting.biometricLockEnabled.defaultValue == false)
        let library = try await library(LockSetting(false))
        #expect(!library.state.isHistoryLocked)
        try await library.add("open words")
        #expect(library.store.items.map(\.displayPreviewText) == ["open words"])
    }

    @Test("with the lock on, a launch is locked and the history is not read into memory until the unlock")
    func whenOnAtLaunch_thenLockedAndUnread() async throws {
        let library = try await library(LockSetting(true))

        #expect(library.state.isHistoryLocked)
        #expect(library.store.fetchCount == 0)

        #expect(await library.state.unlockHistory())
        #expect(!library.state.isHistoryLocked)
        #expect(library.store.fetchCount > 0)
    }

    @Test("away for less than the timeout stays open; away for the timeout locks on return")
    func whenAway_thenTheTimeoutDecides() async throws {
        let setting = LockSetting(true)
        let time = TimeBox()
        let library = try await library(setting, time: time)
        await library.state.unlockHistory()

        library.state.didLeaveForeground()
        time.advance(by: 4 * 60)
        library.state.lockDidBecomeActive()
        #expect(!library.state.isHistoryLocked)

        library.state.didLeaveForeground()
        time.advance(by: 5 * 60)
        library.state.lockDidBecomeActive()
        #expect(library.state.isHistoryLocked)
    }

    @Test("the timeout is the one authentication window the Mac uses")
    func whenTimeoutChanged_thenItIsTheGraceWindow() async throws {
        let defaults = ThrowawayDefaults.make()
        defaults.set(15, forKey: Setting.authenticationGraceMinutes.name)
        #expect(AuthenticationGrace.minutes(defaults: defaults) == 15)

        let setting = LockSetting(true)
        setting.minutes = 15
        let time = TimeBox()
        let library = try await library(setting, time: time)
        await library.state.unlockHistory()
        library.state.didLeaveForeground()
        time.advance(by: 10 * 60)
        library.state.lockDidBecomeActive()
        #expect(!library.state.isHistoryLocked)
    }

    @Test("a refused prompt keeps it locked; with nothing to authenticate it stays locked and can be turned off")
    func whenUnlockFailsOrCannotAsk_thenStillLocked() async throws {
        let refused = try await library(LockSetting(true), grants: false)
        #expect(await !refused.state.unlockHistory())
        #expect(refused.state.isHistoryLocked)

        let setting = LockSetting(true)
        let cannot = try await library(setting, available: false)
        #expect(await !cannot.state.unlockHistory())
        #expect(cannot.state.isHistoryLocked)
        setting.isOn = false
        cannot.state.historyLockSettingChanged()
        #expect(!cannot.state.isHistoryLocked)
    }

    @Test("locking drops the search text, the opened previews, Undo, its offer and every shown clip")
    func whenLocked_thenNothingDecryptedStays() async throws {
        let library = try await library(LockSetting(true))
        await library.state.unlockHistory()
        let note = try await library.add("searchable note")
        try await library.service.ingest(#require(ClipCapture.text(secret)))
        let hidden = try await library.settle()
        await library.state.secretReveal.show(hidden.id, reason: "test")
        library.state.secretReveal.isHiddenByHand = true
        library.state.secretReveal.showUnderCover(note.id)
        await library.state.delete([note.id])
        #expect(library.state.undoOffer != nil)
        #expect(library.service.undoHistory.undoLabel != nil)
        _ = library.store.searchIndex()
        #expect(library.store.hasSearchText)

        library.state.lockHistory()

        #expect(library.state.isHistoryLocked)
        #expect(!library.store.hasSearchText)
        #expect(PreviewTextCache.shared.isEmpty)
        #expect(library.service.undoHistory.undoLabel == nil)
        #expect(library.state.undoOffer == nil)
        #expect(library.state.secretReveal.shown.isEmpty)
        #expect(library.state.secretReveal.shownUnderCover.isEmpty)
    }

    @Test("Shortcuts find nothing while locked, also when Pesto has been away past the timeout without coming back")
    func whenLocked_thenShortcutsFindNothing() async throws {
        let time = TimeBox()
        let library = try await library(LockSetting(true), time: time)
        await library.state.unlockHistory()
        let note = try await library.add("findable note")
        #expect(try library.state.searchForShortcut("findable").count == 1)

        library.state.didLeaveForeground()
        time.advance(by: 6 * 60)

        #expect(try library.state.searchForShortcut("findable").isEmpty)
        #expect(try library.state.shortcutClips(ids: [note.id]).isEmpty)
        #expect(library.state.isHistoryLocked)
        #expect(!library.store.hasSearchText)

        await library.state.unlockHistory()
        #expect(try library.state.shortcutClips(ids: [note.id]).count == 1)
    }

    private struct Surfaces {
        let quick: QuickInsertTarget
        let widget: WidgetTarget

        func quickCount() throws -> Int {
            try quick.file.read(with: #require(try quick.keys.key())).entries.count
        }

        func widgetSnapshot() throws -> WidgetSnapshot {
            try widget.file.read(WidgetSnapshot.self, with: #require(try widget.keys.key()))
        }
    }

    private func surfaces(_ library: MobileTestLibrary, root: URL) -> Surfaces {
        let quick = QuickInsertTarget(
            file: QuickInsertFile(root: root), keys: QuickInsertKeyStore(secrets: MemorySecrets()), isEnabled: { true }
        )
        let widget = WidgetTarget(
            file: SealedGroupFile(root: root, format: .widgetSnapshot),
            keys: SharedFileKeyStore(secrets: MemorySecrets(), account: AppIdentity.widgetKeyAccount),
            isInstalled: { true }, reload: {}
        )
        library.state.quickInsert = quick
        library.state.widget = widget
        return Surfaces(quick: quick, widget: widget)
    }

    @Test("with the lock on, the widget says Locked and the AutoFill set is empty, from the moment it is on")
    func whenLockOn_thenOutsideSurfacesHoldNothing() async throws {
        let setting = LockSetting(false)
        let library = try await library(setting)
        let root = try temporaryFolder("lock-surfaces")
        defer { try? FileManager.default.removeItem(at: root) }
        let surfaces = surfaces(library, root: root)
        try await library.add("a pinned address")
        library.state.writeQuickInsert()
        await library.state.refreshWidgetPresence()
        #expect(try surfaces.quickCount() == 1)
        #expect(try surfaces.widgetSnapshot().clips.count == 1)

        setting.isOn = true
        library.state.historyLockSettingChanged()

        #expect(try surfaces.quickCount() == 0)
        #expect(try surfaces.widgetSnapshot().isLocked)
        #expect(try surfaces.widgetSnapshot().clips.isEmpty)
        #expect(WidgetContent(snapshot: surfaces.widgetSnapshot(), size: .medium).state == .locked)

        try await library.add("another clip")
        library.state.writeQuickInsert()
        library.state.didLeaveForeground()
        await library.state.refreshWidgetPresence()
        #expect(try surfaces.quickCount() == 0)
        #expect(try surfaces.widgetSnapshot().isLocked)
    }

    @Test("with Show clips in widgets and AutoFill on, they are written as without the lock, and the toggle moves them")
    func whenShowsOutside_thenTheyAreWrittenAsWithoutTheLock() async throws {
        let setting = LockSetting(true)
        setting.showsOutside = true
        let library = try await library(setting)
        let root = try temporaryFolder("lock-surfaces-shown")
        defer { try? FileManager.default.removeItem(at: root) }
        let surfaces = surfaces(library, root: root)
        try await library.add("a pinned address")
        try await library.service.ingest(#require(ClipCapture.text(secret)))
        try await library.refreshed()

        library.state.writeQuickInsert()
        await library.state.refreshWidgetPresence()
        #expect(try surfaces.quickCount() == 1)
        #expect(try surfaces.widgetSnapshot().clips.map(\.text) == ["a pinned address"])
        #expect(try !surfaces.widgetSnapshot().isLocked)

        library.state.lockHistory()
        #expect(try surfaces.quickCount() == 1)
        #expect(try surfaces.widgetSnapshot().clips.count == 1)

        setting.showsOutside = false
        library.state.showsClipsOutsideSettingChanged()
        #expect(try surfaces.quickCount() == 0)
        #expect(try surfaces.widgetSnapshot().isLocked)

        setting.showsOutside = true
        library.state.showsClipsOutsideSettingChanged()
        #expect(try surfaces.quickCount() == 1)
        #expect(try surfaces.widgetSnapshot().clips.count == 1)
    }

    @Test("the toggle is off by default and a key of the settings registry")
    func whenDefault_thenOff() {
        #expect(Setting.showsClipsOutsideWhileLocked.defaultValue == false)
        #expect(Setting.allNames.contains(Setting.showsClipsOutsideWhileLocked.name))
    }

    @Test("what was shared waits in the inbox until the history is unlocked")
    func whenLocked_thenTheInboxWaits() async throws {
        let library = try await library(LockSetting(true))
        let root = try temporaryFolder("lock-inbox")
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = SharedInbox(root: root)
        let keys = InboxKeyStore(secrets: MemorySecrets())
        try inbox.publish(InboxPublicKey(keys.loadOrCreate().publicKey))
        try inbox.deposit(#require(InboxItem.text("shared while locked")))

        #expect(await library.state.drainInbox(inbox, keys: keys) == nil)
        #expect(inbox.pendingFiles().count == 1)

        await library.state.unlockHistory()
        let report = try #require(await library.state.drainInbox(inbox, keys: keys))
        #expect(report.added == 1)
        #expect(inbox.pendingFiles().isEmpty)
    }

    @Test("a widget link that arrives while locked is held, and acted on once unlocked")
    func whenLocked_thenAWidgetLinkWaits() async throws {
        let library = try await library(LockSetting(true))
        await library.state.unlockHistory()
        let note = try await library.add("from the widget")
        library.state.lockHistory()
        let link = try #require(URL(string: "pesto://clip/\(note.id.uuidString)/show"))

        #expect(library.state.open(link) == .ignored)
        #expect(library.state.linkedClip == nil)

        await library.state.unlockHistory()
        #expect(library.state.linkedClip?.id == note.id)
        #expect(library.state.linkedClip?.opensDetail == true)
    }

    @Test("sync is told the history is locked, as the Mac's is, so it pauses until the unlock")
    func whenLocked_thenSyncIsPaused() async throws {
        let library = try await library(LockSetting(true))
        let check = library.state.syncLockCheck
        #expect(check())
        await library.state.unlockHistory()
        #expect(!check())
        library.state.lockHistory()
        #expect(check())
    }

    @Test("the lock screen asks by itself only while it is shown and the history is locked")
    func whenShown_thenThePromptIsAutomatic() {
        #expect(HistoryLockPolicy.shouldPromptAutomatically(isLocked: true, isVisible: true))
        #expect(!HistoryLockPolicy.shouldPromptAutomatically(isLocked: true, isVisible: false))
        #expect(!HistoryLockPolicy.shouldPromptAutomatically(isLocked: false, isVisible: true))
    }
}
