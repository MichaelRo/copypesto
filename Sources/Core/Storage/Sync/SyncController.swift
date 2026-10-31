// SPDX-License-Identifier: MIT
import Foundation
import Observation
import SwiftData

/// What Settings shows while sync is being turned on, joined or paired. Each case is one screen of the design.
public enum SyncFlow: Equatable, Sendable {
    case idle
    case setUp
    case joinOffer(thisMac: Int, group: Int)
    case iCloudKeychainOff
    case needsKey
    case pairing(words: [String], approver: String)
    case enterRecoveryKey
    case recoveryKey(String)
    case failed(String)
}

public struct SyncPendingJoin: Equatable, Sendable {
    public let request: SyncJoinRequest
    public let words: [String]

    public init(request: SyncJoinRequest, words: [String]) {
        self.request = request
        self.words = words
    }
}

/// Everything the Settings UI asks of sync, in one place that can be tested without a window: turning it on, joining
/// a group, asking another Mac for the key, allowing a Mac, Reset Sync and Leave Sync. It owns the folder service while
/// sync is on. The UI only reads its state and calls these.
@MainActor
@Observable
public final class SyncController {
    public struct Environment {
        public var container: ModelContainer
        public var storage: StorageService
        public var folder: URL
        public var keyStore: any SyncKeyStoring
        public var deviceKeys: any SyncDeviceKeyStoring
        public var highWater: any SyncHighWaterStoring
        public var defaults: UserDefaults
        public var deviceID: String
        public var deviceName: String
        public var isLocked: @MainActor () -> Bool = { false }
        public var now: @Sendable () -> Date = { .now }
        public var timing = SyncFolderService.Timing()

        public init(
            container: ModelContainer, storage: StorageService, folder: URL, keyStore: any SyncKeyStoring,
            deviceKeys: any SyncDeviceKeyStoring, highWater: any SyncHighWaterStoring, defaults: UserDefaults,
            deviceID: String, deviceName: String
        ) {
            self.container = container
            self.storage = storage
            self.folder = folder
            self.keyStore = keyStore
            self.deviceKeys = deviceKeys
            self.highWater = highWater
            self.defaults = defaults
            self.deviceID = deviceID
            self.deviceName = deviceName
        }
    }

    public private(set) var status: SyncStatus = .off
    public private(set) var flow: SyncFlow = .idle
    public private(set) var isEnabled: Bool
    public private(set) var keepsHere = 0
    public private(set) var pendingJoin: SyncPendingJoin?

    private var env: Environment
    private let baseDeviceID: String
    private var service: SyncFolderService?
    private var identity: SyncIdentity?
    private var approverID: String?
    private var ignored: Set<String> = []

    /// "Pesto \u{203A} Pesto Sync": the last two parts of the folder, how a person would say where it is.
    public var folderDisplayName: String {
        [env.folder.deletingLastPathComponent().lastPathComponent, env.folder.lastPathComponent]
            .joined(separator: " \u{203A} ")
    }

    public var keyMode: SyncKeyMode {
        env.keyStore.mode
    }

    public var folderURL: URL {
        env.folder
    }

    public var includesSecrets: Bool {
        env.defaults.value(for: Setting.syncIncludesSecrets)
    }

    public init(_ environment: Environment) {
        env = environment
        baseDeviceID = environment.deviceID
        isEnabled = environment.defaults.value(for: Setting.syncEnabled)
        env.deviceID = Self.syncDeviceID(
            base: baseDeviceID,
            serial: environment.defaults.value(for: Setting.syncDeviceSerial)
        )
    }

    /// A Mac that leaves and joins again is a new device to the others: the log it wrote before is gone, and its new
    /// sequence numbers would otherwise fall below the marks they hold for the old one.
    private static func syncDeviceID(base: String, serial: Int) -> String {
        serial == 0 ? base : "\(base)-\(serial)"
    }

    // MARK: Turning on

    public func beginSetUp() {
        flow = .setUp
    }

    public func beginRecoveryKeyEntry() {
        flow = .enterRecoveryKey
    }

    public func cancelFlow() {
        flow = .idle
        approverID = nil
    }

    public func chooseFolder(_ url: URL) {
        env.folder = url
        env.defaults.set(url.path, for: Setting.syncFolderPath)
    }

    /// Moves this Mac to another folder: sync stops here, the old folder is left exactly as it is, and the set-up sheet
    /// opens for the new one (a new group there, or an offer to join the one that is).
    public func changeFolder(to url: URL) {
        pause()
        env.highWater.save(SyncHighWater())
        chooseFolder(url)
        flow = .setUp
    }

    /// Looks at the folder: makes a new group when it is empty, offers to join one that is there, or says why the key
    /// is
    /// not available. Nothing is written for a group that exists until the person confirms.
    public func turnOn() async {
        do {
            let me = try loadIdentity()
            let layout = SyncFolderLayout(root: env.folder)
            switch try openGroup() {
            case .empty:
                let made = try SyncGroupManager.create(
                    layout: layout,
                    identity: me,
                    keyStore: env.keyStore,
                    now: env.now()
                )
                flow = .recoveryKey(made.recoveryKey)
                enable()
            case let .ready(group):
                let mine = (try? env.container.mainContext.fetchCount(FetchDescriptor<ClipboardItem>())) ?? 0
                let theirs = SyncGroupSurvey.clipCount(layout: layout, group: group, excluding: me.deviceID)
                flow = .joinOffer(thisMac: mine, group: theirs)
            case .needsKey:
                flow = env.keyStore.mode == .iCloudKeychain ? .iCloudKeychainOff : .needsKey
            }
        } catch {
            flow = .failed(Self.describe(error))
        }
    }

    public func confirmJoin() {
        flow = .idle
        enable()
    }

    private func loadIdentity() throws -> SyncIdentity {
        if let identity { return identity }
        let keys: SyncDeviceKeys
        if let stored = try env.deviceKeys.deviceKeys() {
            keys = stored
        } else {
            keys = .generate()
            try env.deviceKeys.saveDeviceKeys(keys)
        }
        let me = SyncIdentity(deviceID: env.deviceID, name: env.deviceName, keys: keys)
        identity = me
        return me
    }

    private func enable() {
        guard let me = identity else { return }
        env.defaults.set(true, for: Setting.syncEnabled)
        isEnabled = true
        SyncJournal.enable(
            for: env.container,
            clock: SyncClock(deviceID: me.deviceID, defaults: env.defaults, now: env.now)
        )
        let defaults = env.defaults
        let created = SyncFolderService(
            container: env.container, storage: env.storage, layout: SyncFolderLayout(root: env.folder), identity: me,
            keyStore: env.keyStore, highWater: env.highWater, timing: env.timing,
            includeSensitive: { defaults.value(for: Setting.syncIncludesSecrets) }, isLocked: env.isLocked, now: env.now
        )
        created.onStatusChange = { [weak self] new in self?.status = new }
        service?.stop()
        service = created
        created.start()
        refreshHeldCount()
    }

    /// Starts sync again at launch when it was on.
    public func resumeIfEnabled() {
        guard isEnabled, service == nil, (try? loadIdentity()) != nil else { return }
        enable()
    }

    public func syncNow() async {
        _ = await service?.syncNow()
        refresh()
    }

    // MARK: The key is not here

    public func useRecoveryKey(_ text: String) async {
        do {
            let key = try SyncKey(recoveryKey: text)
            guard case let .needsKey(vault) = try openGroup() else {
                flow = .failed("There is no Pesto sync in this folder.")
                return
            }
            guard vault.accepts(key) else {
                flow = .failed("That recovery key does not open the sync in this folder. Check it for a typo.")
                return
            }
            try env.keyStore.saveSyncKey(key, vaultID: vault.vaultID, epoch: vault.epoch)
            await turnOn()
        } catch {
            flow = .failed(Self.describe(error))
        }
    }

    public func askAnotherMac() {
        do {
            let me = try loadIdentity()
            let layout = SyncFolderLayout(root: env.folder)
            guard case let .needsKey(vault) = try openGroup() else { return }
            guard let approver = Self.publicIdentities(layout).first(where: { $0.deviceID != me.deviceID }) else {
                flow =
                    .failed("No other Mac has announced itself in this folder yet. Open Pesto on the other Mac first.")
                return
            }
            let request = try SyncJoinRequest(
                deviceID: me.deviceID, name: me.name, keys: me.keys.publicKeys, vaultID: vault.vaultID,
                approverKeyID: approver.keys.keyID, createdAt: env.now()
            ).signed(by: me.keys)
            try FileManager.default.createDirectory(at: layout.device(me.deviceID), withIntermediateDirectories: true)
            try request.serialized().write(to: layout.joinRequest(me.deviceID), options: .atomic)
            approverID = approver.deviceID
            flow = .pairing(words: request.pairingWords(approver: approver.keys), approver: approver.name)
        } catch {
            flow = .failed(Self.describe(error))
        }
    }

    // MARK: Looking for requests and grants (called by a timer while Settings is open)

    public func refresh() {
        refreshHeldCount()
        let layout = SyncFolderLayout(root: env.folder)
        if case .pairing = flow { collectGrant(layout) }
        pendingJoin = isEnabled ? findJoinRequest(layout) : nil
    }

    private func collectGrant(_ layout: SyncFolderLayout) {
        guard let me = identity, let approverID else { return }
        let url = layout.grants(approverID).appendingPathComponent("\(me.deviceID).pestogrant")
        guard let data = try? Data(contentsOf: url), let grant = try? SyncGrant.parse(data),
              let approver = Self.publicIdentities(layout).first(where: { $0.deviceID == approverID }),
              case let .needsKey(vault) = try? openGroup() else { return }
        do {
            let opened = try grant.open(
                device: me.keys, deviceID: me.deviceID, vaultID: vault.vaultID, expectedApprover: approver.keys
            )
            try env.keyStore.saveSyncKey(opened.key, vaultID: vault.vaultID, epoch: opened.epoch)
            try? FileManager.default.removeItem(at: layout.joinRequest(me.deviceID))
            self.approverID = nil
            Task { await turnOn() }
        } catch {
            flow = .failed("The key from the other Mac did not open. Ask again.")
        }
    }

    private func findJoinRequest(_ layout: SyncFolderLayout) -> SyncPendingJoin? {
        guard let me = identity else { return nil }
        for id in layout.deviceIDs() where id != me.deviceID {
            guard let data = try? Data(contentsOf: layout.joinRequest(id)),
                  let request = try? SyncJoinRequest.parse(data),
                  request.approverKeyID == me.keys.publicKeys.keyID, !ignored.contains(request.deviceID),
                  !FileManager.default.fileExists(atPath: layout.grants(me.deviceID)
                      .appendingPathComponent("\(request.deviceID).pestogrant").path) else { continue }
            return SyncPendingJoin(request: request, words: request.pairingWords(approver: me.keys.publicKeys))
        }
        return nil
    }

    public func allow(_ pending: SyncPendingJoin) {
        guard let me = identity else { return }
        let layout = SyncFolderLayout(root: env.folder)
        do {
            guard case let .ready(group) = try openGroup() else { return }
            let grant = try SyncGrant.seal(
                key: group.key, vaultID: group.vault.vaultID, epoch: group.epoch, to: pending.request, approver: me.keys
            )
            try FileManager.default.createDirectory(at: layout.grants(me.deviceID), withIntermediateDirectories: true)
            try grant.serialized().write(
                to: layout.grants(me.deviceID).appendingPathComponent("\(pending.request.deviceID).pestogrant"),
                options: .atomic
            )
            pendingJoin = nil
        } catch {
            flow = .failed(Self.describe(error))
        }
    }

    public func deny(_ pending: SyncPendingJoin) {
        ignored.insert(pending.request.deviceID)
        pendingJoin = nil
    }

    // MARK: Settings

    public func setIncludesSecrets(_ on: Bool) async {
        env.defaults.set(on, for: Setting.syncIncludesSecrets)
        // What may leave this Mac changed: write everything that now may, or withdraw what no longer may.
        _ = try? await env.storage.restampForSync(.sensitive)
        refreshHeldCount()
        await syncNow()
    }

    public func showRecoveryKey() -> String? {
        guard case let .ready(group) = try? openGroup() else { return nil }
        return group.key.recoveryKey
    }

    /// Shows the recovery key again (the caller has asked for fresh authentication first).
    public func presentRecoveryKey() {
        if let key = showRecoveryKey() { flow = .recoveryKey(key) }
    }

    public func reset() async {
        do {
            let me = try loadIdentity()
            let layout = SyncFolderLayout(root: env.folder)
            guard case let .ready(group) = try openGroup() else { return }
            let next = try SyncGroupManager.reset(
                layout: layout, from: group, identity: me, keyStore: env.keyStore, now: env.now()
            )
            flow = .recoveryKey(next.recoveryKey)
            await syncNow()
        } catch {
            flow = .failed(Self.describe(error))
        }
    }

    /// Turns sync off and leaves the group: this Mac's own files go from the folder and its marks are forgotten. The
    /// other Macs keep everything, and clips already on this Mac stay.
    public func leave() {
        if let me = identity ?? (try? loadIdentity()) {
            if let message = removeThisMacFromFolder(me.deviceID) {
                flow = .failed(message)
                return
            }
        }
        service?.stop()
        service = nil
        SyncJournal.disable(for: env.container)
        env.highWater.save(SyncHighWater())
        let serial: Int = env.defaults.value(for: Setting.syncDeviceSerial) + 1
        env.defaults.set(serial, for: Setting.syncDeviceSerial)
        env.deviceID = Self.syncDeviceID(base: baseDeviceID, serial: serial)
        identity = nil
        env.defaults.set(false, for: Setting.syncEnabled)
        isEnabled = false
        status = .off
        flow = .idle
    }

    /// Says in the folder that this Mac left (so the others take over its clips), then removes its folder. Returns what
    /// went wrong, in words, or nil.
    private func removeThisMacFromFolder(_ deviceID: String) -> String? {
        let layout = SyncFolderLayout(root: env.folder)
        let folder = layout.device(deviceID)
        do {
            let marker = layout.leftMarker(deviceID)
            try FileManager.default.createDirectory(
                at: marker.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data().write(to: marker, options: .atomic)
            if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
            return nil
        } catch {
            return "Pesto could not remove this Mac's files from the folder, so sync is still on. " +
                error.localizedDescription
        }
    }

    /// Stops reading and writing now and leaves the folder alone.
    public func pause() {
        service?.stop()
        service = nil
        SyncJournal.disable(for: env.container)
        env.defaults.set(false, for: Setting.syncEnabled)
        isEnabled = false
        status = .off
    }

    private func openGroup() throws -> SyncGroupOpening {
        try SyncGroupManager.open(layout: SyncFolderLayout(root: env.folder), keyStore: env.keyStore)
    }

    private func refreshHeldCount() {
        let secrets = includesSecrets
        let context = ModelContext(env.container)
        let big = AutoBackupSettings.largestClipBytes
        let descriptor = secrets
            ?
            FetchDescriptor<ClipboardItem>(predicate: #Predicate {
                $0.sensitivityRaw == "credential" || $0.byteSize > big
            })
            : FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.sensitivityRaw != nil || $0.byteSize > big })
        keepsHere = (try? context.fetchCount(descriptor)) ?? 0
    }

    private static func publicIdentities(_ layout: SyncFolderLayout) -> [SyncPublicIdentity] {
        layout.deviceIDs().compactMap { id in
            (try? Data(contentsOf: layout.identity(id))).flatMap { try? SyncPublicIdentity.parse($0) }
        }
    }

    static func describe(_ error: any Error) -> String {
        switch error {
        case SyncKeyStoreError.entitlementMissing: "This build cannot use iCloud Keychain. Use a recovery key instead."
        case SyncKeyStoreError.locked: "The Keychain is locked. Unlock the Mac and try again."
        case SyncKeyStoreError.conflict: "A different key is already stored for this sync."
        default: "Sync could not continue: \(error.localizedDescription)"
        }
    }
}
