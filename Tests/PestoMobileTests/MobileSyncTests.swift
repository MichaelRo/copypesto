// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

/// The iOS app's side of sync as the app builds it: a picked folder kept as a bookmark, a this-device key in memory,
/// its own store, and an iPhone's words. The other side is a Mac built the way the Mac app builds it.
@MainActor
final class MobileSyncDevice {
    let library: MobileTestLibrary
    let sync: MobileSync
    let defaults = ThrowawayDefaults.make()
    let secrets = MemorySecrets()
    let bookmarks = FakeBookmarks()

    init(time: TimeBox, name: String = "iphone-b", lock: MobileHistoryLock? = nil) async throws {
        library = try await MobileTestLibrary(lock: lock)
        let isLocked = library.state.syncLockCheck
        let container = try #require(library.state.historyContainer)
        let storage = library.service
        let defaults = defaults
        let secrets = secrets
        sync = MobileSync(MobileSync.Environment(
            folder: BookmarkedSyncFolder(defaults: defaults, bookmarks: bookmarks), deviceKind: .iPhone,
            defaults: defaults, authenticator: StubUserAuthenticator(available: true, grants: true),
            grace: AuthenticationGrace(),
            makeController: { root in
                var environment = SyncController.Environment(
                    container: container, storage: storage, folder: root,
                    keyStore: ThisDeviceSyncKeyStore(secrets: secrets),
                    deviceKeys: KeychainDeviceKeyStore(secrets: secrets), highWater: MemoryHighWater(),
                    defaults: defaults, deviceID: name, deviceName: "iPhone"
                )
                environment.deviceKind = .iPhone
                environment.isLocked = isLocked
                environment.now = { time.now }
                environment.timing.batchWindow = .milliseconds(20)
                environment.timing.pollInterval = .seconds(3600)
                return SyncController(environment)
            }
        ))
        library.state.sync = sync
    }

    func clips() async throws -> [String] {
        try await library.refreshed()
        return library.store.items.map(\.displayPreviewText).sorted()
    }
}

@Suite("Sync on an iPhone, with a Mac, through a folder", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct MobileSyncTests {
    let picked: URL
    let time = TimeBox()

    init() throws {
        picked = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-mobile-sync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
    }

    private var root: URL {
        picked.appendingPathComponent(BookmarkedSyncFolder.folderName, isDirectory: true)
    }

    private func exchange(_ mac: SyncMac, _ phone: MobileSyncDevice) async {
        for _ in 0..<2 {
            time.advance()
            await mac.controller.syncNow()
            time.advance()
            await phone.sync.syncNow()
        }
    }

    private func waitForJoinOffer(_ sync: MobileSync) async throws {
        for _ in 0..<100 {
            if case .joinOffer = sync.flow { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("expected an offer to join, got \(sync.flow)")
    }

    private func firstMac() async throws -> (mac: SyncMac, key: String) {
        let mac = try SyncMac(name: "mac-a", folder: root, time: time)
        try await mac.site.copy("from the Mac")
        await mac.controller.turnOn()
        guard case let .recoveryKey(key) = mac.controller.flow else {
            throw CocoaError(.featureUnsupported)
        }
        mac.controller.cancelFlow()
        time.advance()
        await mac.controller.syncNow()
        return (mac, key)
    }

    @Test("a Mac and an iPhone that joined with the recovery key exchange clips both ways")
    func whenTheIPhoneJoinsWithTheRecoveryKey_thenClipsTravelBothWays() async throws {
        defer { try? FileManager.default.removeItem(at: picked) }
        let (mac, key) = try await firstMac()
        let phone = try await MobileSyncDevice(time: time)
        try await phone.library.add("from the iPhone")

        phone.sync.activate()
        #expect(!phone.sync.hasFolder)
        phone.sync.useFolder(picked)
        #expect(phone.sync.flow == .setUp)
        #expect(phone.sync.controller?.folderURL.standardizedFileURL == root.standardizedFileURL)
        await phone.sync.turnOn()
        #expect(phone.sync.flow == .needsKey)
        await phone.sync.useRecoveryKey(key)
        guard case let .joinOffer(here, _) = phone.sync.flow else {
            Issue.record("expected an offer to join, got \(phone.sync.flow)")
            return
        }
        #expect(here == 1)
        phone.sync.confirmJoin()
        #expect(phone.sync.isEnabled)

        await exchange(mac, phone)

        #expect(try mac.clips() == ["from the Mac", "from the iPhone"], "Mac: \(mac.controller.status)")
        #expect(try await phone.clips() == ["from the Mac", "from the iPhone"], "iPhone: \(phone.sync.status)")
        #expect(phone.sync.status.tone == .good)

        try await mac.site.copy("later, on the Mac")
        try await phone.library.add("later, on the iPhone")
        await exchange(mac, phone)
        #expect(try mac.clips().contains("later, on the iPhone"))
        #expect(try await phone.clips().contains("later, on the Mac"))
    }

    @Test("an iPhone whose history is locked pauses sync, as a locked Mac does, and catches up once unlocked")
    func whenTheIPhoneIsLocked_thenSyncPausesUntilTheUnlock() async throws {
        defer { try? FileManager.default.removeItem(at: picked) }
        let (mac, key) = try await firstMac()
        let setting = MobileHistoryLockTests.LockSetting(false)
        let lock = MobileHistoryLock(
            authenticator: StubUserAuthenticator(available: true, grants: true), grace: AuthenticationGrace(),
            isEnabled: { setting.isOn }
        )
        let phone = try await MobileSyncDevice(time: time, lock: lock)
        phone.sync.activate()
        phone.sync.useFolder(picked)
        await phone.sync.turnOn()
        await phone.sync.useRecoveryKey(key)
        phone.sync.confirmJoin()
        await exchange(mac, phone)
        #expect(try await phone.clips() == ["from the Mac"])

        setting.isOn = true
        phone.library.state.lockHistory()
        try await mac.site.copy("while the iPhone is locked")
        await exchange(mac, phone)
        #expect(phone.sync.controller?.status == .paused)
        #expect(try await !phone.clips().contains("while the iPhone is locked"))

        await phone.library.state.unlockHistory()
        await exchange(mac, phone)
        #expect(try await phone.clips().contains("while the iPhone is locked"))
    }

    @Test("an iPhone joins by the eight words: both screens show the same words, the Mac allows, the key arrives")
    func whenTheIPhoneAsksTheMac_thenTheWordsMatchAndTheKeyArrives() async throws {
        defer { try? FileManager.default.removeItem(at: picked) }
        let (mac, _) = try await firstMac()
        let phone = try await MobileSyncDevice(time: time)
        phone.sync.activate()
        phone.sync.useFolder(picked)
        await phone.sync.turnOn()
        #expect(phone.sync.flow == .needsKey)

        phone.sync.askAnotherDevice()
        guard case let .pairing(words, approver) = phone.sync.flow else {
            Issue.record("expected the words, got \(phone.sync.flow)")
            return
        }
        #expect(words.count == SyncPairingCode.wordCount)
        #expect(approver == "mac-a’s Mac")
        mac.controller.refresh()
        let pending = try #require(mac.controller.pendingJoin)
        #expect(pending.words == words)
        #expect(pending.request.name == "iPhone")
        mac.controller.allow(pending)

        phone.sync.refresh()
        try await waitForJoinOffer(phone.sync)
        phone.sync.confirmJoin()
        await exchange(mac, phone)
        #expect(try await phone.clips() == ["from the Mac"])
    }

    @Test("an iPhone that is already in sync approves a Mac that asks it, after the words match")
    func whenAMacAsksTheIPhone_thenTheIPhoneApprovesIt() async throws {
        defer { try? FileManager.default.removeItem(at: picked) }
        let phone = try await MobileSyncDevice(time: time)
        try await phone.library.add("from the iPhone")
        phone.sync.activate()
        phone.sync.useFolder(picked)
        await phone.sync.turnOn()
        guard case .recoveryKey = phone.sync.flow else {
            Issue.record("the first device is shown the recovery key, got \(phone.sync.flow)")
            return
        }
        phone.sync.cancelFlow()
        time.advance()
        await phone.sync.syncNow()

        let mac = try SyncMac(name: "mac-a", folder: root, time: time)
        await mac.controller.turnOn()
        #expect(mac.controller.flow == .needsKey)
        mac.controller.askAnotherMac()
        guard case let .pairing(words, approver) = mac.controller.flow else {
            Issue.record("expected the words on the Mac, got \(mac.controller.flow)")
            return
        }
        #expect(approver == "iPhone")
        phone.sync.refresh()
        let pending = try #require(phone.sync.pendingJoin)
        #expect(pending.words == words)
        phone.sync.approve(pending)
        #expect(phone.sync.pendingJoin == nil)

        mac.controller.refresh()
        for _ in 0..<100 {
            if case .joinOffer = mac.controller.flow { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        mac.controller.confirmJoin()
        await exchange(mac, phone)
        let macClips = try mac.clips()
        let logs = (FileManager.default.enumerator(atPath: root.path)?.allObjects as? [String]) ?? []
        #expect(
            macClips == ["from the iPhone"],
            "Mac: \(mac.controller.status) iPhone: \(String(describing: phone.sync.controller?.status)) \(logs)"
        )
    }

    @Test(
        "a stale bookmark that cannot be renewed asks for the folder again, sync waits, and the same folder resumes it"
    )
    func whenTheBookmarkGoesStale_thenSyncWaitsForTheFolderAndResumes() async throws {
        defer { try? FileManager.default.removeItem(at: picked) }
        let (mac, key) = try await firstMac()
        let phone = try await MobileSyncDevice(time: time)
        phone.sync.activate()
        phone.sync.useFolder(picked)
        await phone.sync.turnOn()
        await phone.sync.useRecoveryKey(key)
        phone.sync.confirmJoin()
        await exchange(mac, phone)
        #expect(phone.sync.status.tone == .good)

        phone.sync.deactivate()
        #expect(phone.bookmarks.held == 0)
        phone.bookmarks.isStale = true
        phone.bookmarks.refusesBookmark = true
        phone.sync.activate()

        #expect(phone.sync.folderProblem == .stale)
        #expect(phone.sync.status.needsFolder)
        #expect(phone.sync.status.tone == .problem)
        #expect(phone.bookmarks.held == 0)
        try await mac.site.copy("while the folder was lost")
        await exchange(mac, phone)
        #expect(try await !(phone.clips().contains("while the folder was lost")))
        #expect(phone.sync.status.needsFolder)

        phone.bookmarks.isStale = false
        phone.bookmarks.refusesBookmark = false
        phone.sync.useFolder(picked)
        #expect(phone.sync.folderProblem == nil)
        #expect(phone.sync.isEnabled, "the same folder again keeps sync on")
        #expect(phone.sync.flow == .idle)
        await exchange(mac, phone)
        #expect(try await phone.clips().contains("while the folder was lost"))
        phone.sync.deactivate()
        #expect(phone.bookmarks.held == 0)
    }

    @Test("a folder deleted while sync is on reads as a repair, never as up to date")
    func whenTheFolderIsDeleted_thenTheStatusAsksForItAgain() async throws {
        defer { try? FileManager.default.removeItem(at: picked) }
        let phone = try await MobileSyncDevice(time: time)
        phone.sync.activate()
        phone.sync.useFolder(picked)
        await phone.sync.turnOn()
        phone.sync.cancelFlow()
        try await Task.sleep(for: .milliseconds(100))
        await phone.sync.syncNow()
        try FileManager.default.removeItem(at: root)

        await phone.sync.syncNow()

        #expect(phone.sync.status.needsFolder)
        #expect(phone.sync.status.tone != .good)
    }

    @Test("sync that has just been turned on reads as checking, not as up to date, until an exchange completes")
    func whenSyncHasJustBeenTurnedOn_thenItDoesNotReadAsSuccess() async throws {
        defer { try? FileManager.default.removeItem(at: picked) }
        let (mac, key) = try await firstMac()
        let phone = try await MobileSyncDevice(time: time)
        #expect(phone.sync.status.tone != .good)
        phone.sync.activate()
        phone.sync.useFolder(picked)
        #expect(phone.sync.status.tone != .good)
        await phone.sync.turnOn()
        await phone.sync.useRecoveryKey(key)
        #expect(phone.sync.status.tone != .good)

        phone.sync.confirmJoin()

        #expect(phone.sync.isEnabled)
        #expect(phone.sync.status.title == String(localized: "Checking the folder"))
        #expect(phone.sync.status.tone != .good)
        await exchange(mac, phone)
        #expect(phone.sync.status.tone == .good, "\(phone.sync.status)")
    }

    @Test("leaving the foreground stops the exchanges and gives the folder back; returning starts them again")
    func whenTheAppGoesToTheBackground_thenTheFolderIsReleasedAndResumed() async throws {
        defer { try? FileManager.default.removeItem(at: picked) }
        let (mac, key) = try await firstMac()
        let phone = try await MobileSyncDevice(time: time)
        phone.sync.activate()
        phone.sync.useFolder(picked)
        await phone.sync.turnOn()
        await phone.sync.useRecoveryKey(key)
        phone.sync.confirmJoin()
        await exchange(mac, phone)

        phone.sync.deactivate()
        #expect(phone.bookmarks.held == 0)
        #expect(phone.sync.isEnabled)
        try await mac.site.copy("while in the background")
        await exchange(mac, phone)
        #expect(try await !(phone.clips().contains("while in the background")))

        phone.sync.activate()
        #expect(phone.bookmarks.held == 1)
        await exchange(mac, phone)
        #expect(try await phone.clips().contains("while in the background"))
        phone.sync.deactivate()
    }

    @Test("a background refresh that ends after the app came back to the front leaves sync running in front")
    func whenTheBackgroundRefreshEndsInFront_thenSyncKeepsRunning() async throws {
        defer { try? FileManager.default.removeItem(at: picked) }
        let (mac, key) = try await firstMac()
        let phone = try await MobileSyncDevice(time: time)
        phone.sync.activate()
        phone.sync.useFolder(picked)
        await phone.sync.turnOn()
        await phone.sync.useRecoveryKey(key)
        phone.sync.confirmJoin()
        await exchange(mac, phone)
        phone.sync.deactivate()
        #expect(phone.bookmarks.held == 0)

        phone.sync.activate(for: .background)
        phone.sync.activate()
        phone.sync.deactivate(for: .background)

        #expect(phone.bookmarks.held == 1, "the app in front still holds the folder")
        try await mac.site.copy("after the refresh ended")
        await exchange(mac, phone)
        #expect(try await phone.clips().contains("after the refresh ended"))

        phone.sync.deactivate()
        #expect(phone.bookmarks.held == 0)
    }

    @Test("turning sync off on the iPhone keeps its place: turning it on again offers to rejoin in the same folder")
    func whenTurnedOff_thenNothingIsExchanged() async throws {
        defer { try? FileManager.default.removeItem(at: picked) }
        let phone = try await MobileSyncDevice(time: time)
        phone.sync.activate()
        phone.sync.useFolder(picked)
        await phone.sync.turnOn()
        phone.sync.cancelFlow()
        phone.sync.turnOff()
        #expect(!phone.sync.isEnabled)
        #expect(phone.sync.status.title == String(localized: "Off"))
        #expect(phone.sync.folderName?.hasSuffix(BookmarkedSyncFolder.folderName) == true)
    }
}
