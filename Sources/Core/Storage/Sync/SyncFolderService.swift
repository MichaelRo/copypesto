// SPDX-License-Identifier: MIT
import Foundation
import os
import SwiftData

private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "SyncFolderService")

/// Keeps this Mac's log and the other Macs' logs in step through the sync folder (ADR 0018). It writes what changed
/// here
/// (a batch window after a save), reads what the others wrote (a folder watcher, with a poll as a fallback), applies it
/// through `StorageService.applySync`, and always has a real state to show. A paste, a capture and the shelf never wait
/// for it. Nothing here uses the network: the folder's own provider (iCloud Drive) is the only transport.
@MainActor
public final class SyncFolderService {
    public struct Timing: Sendable {
        public var batchWindow: Duration = .seconds(1)
        public var pollInterval: Duration = .seconds(30)
        public var quietAfter: TimeInterval = 6 * 3600
        public var compactAfterSegments = 100
        public var batchesPerPass = 20

        public init() {}
    }

    private let container: ModelContainer
    let storage: StorageService
    let layout: SyncFolderLayout
    let identity: SyncIdentity
    private let keyStore: any SyncKeyStoring
    private let highWaterStore: any SyncHighWaterStoring
    let includeSensitive: @MainActor () -> Bool
    private let isLocked: @MainActor () -> Bool
    private let isReadable: @Sendable (URL) -> Bool
    let folderProbe: FolderProbe
    let now: @Sendable () -> Date
    let timing: Timing
    private let deviceKind: SyncDeviceKind

    public private(set) var status: SyncStatus = .off
    public var onStatusChange: (@MainActor (SyncStatus) -> Void)?
    public var onPeerDevicesChange: (@MainActor ([String: String]) -> Void)?
    /// The apps another device's clips came from (ADR 0068), each time a catalog is read.
    public var onAppCatalog: (@MainActor ([SyncAppCatalog.Entry]) -> Void)?

    private var group: SyncGroup?
    private var water: SyncHighWater
    private var savedWater: SyncHighWater
    private var stopped = false
    var ownLast: (sequence: UInt64, hash: String) = (0, SyncManifest.zeroHash)
    private var ownLogRecovered = false
    private var lastReceived: Date?
    private var current: Task<Void, Never>?
    var segmentsAfterCompaction = 0
    private var again = false
    private var pending: Task<Void, Never>?
    private var loop: Task<Void, Never>?
    private var observer: (any NSObjectProtocol)?
    private var watcher: SyncFolderWatcher?
    /// What this device last wrote to its app catalog in this run, so an unchanged list is not written again, and the
    /// last sequence it was checked at: an idle pass (nothing new written) does not look at the history again.
    private var writtenCatalog: [SyncAppCatalog.Entry]?
    private var catalogCheckedAt: UInt64?
    /// When each other device's catalog file last changed, so an idle pass reads none of them again.
    private var readCatalogDates: [String: Date] = [:]

    public init(
        container: ModelContainer, storage: StorageService, layout: SyncFolderLayout, identity: SyncIdentity,
        keyStore: any SyncKeyStoring, highWater: any SyncHighWaterStoring, timing: Timing = Timing(),
        includeSensitive: @escaping @MainActor () -> Bool = { false },
        isLocked: @escaping @MainActor () -> Bool = { false },
        isReadable: (@Sendable (URL) -> Bool)? = nil,
        folderProbe: FolderProbe = FolderProbe(),
        now: @escaping @Sendable () -> Date = { .now },
        deviceKind: SyncDeviceKind = .mac
    ) {
        self.deviceKind = deviceKind
        self.container = container
        self.storage = storage
        self.layout = layout
        self.identity = identity
        self.keyStore = keyStore
        highWaterStore = highWater
        water = highWater.load()
        savedWater = water
        self.timing = timing
        self.includeSensitive = includeSensitive
        self.isLocked = isLocked
        self.isReadable = isReadable ?? { SyncFileAvailability.isReadable($0) }
        self.folderProbe = folderProbe
        self.now = now
    }

    // MARK: Running

    public func start() {
        guard loop == nil else { return }
        stopped = false
        observer = ModelSaveObserver.observeChanges(in: container) { [weak self] _ in self?.scheduleSoon() }
        watcher = SyncFolderWatcher(url: layout.root) { [weak self] in
            Task { @MainActor in self?.scheduleSoon() }
        }
        try? FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
        watcher?.start()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncNow()
                try? await Task.sleep(for: self?.timing.pollInterval ?? .seconds(30))
            }
        }
    }

    /// Also ends a pass that is running: an iPhone stops when its folder's security scope is about to end.
    public func stop() {
        stopped = true
        current?.cancel()
        loop?.cancel()
        pending?.cancel()
        loop = nil
        pending = nil
        watcher?.stop()
        watcher = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        group = nil
        onPeerDevicesChange?([:])
        set(.off)
    }

    /// A pass that was in flight when the person left sync or changed the folder must not write its marks back over
    /// the fresh ones the controller saved, and an unchanged mark is not written again.
    private func saveWater() {
        guard !stopped, water != savedWater else { return }
        highWaterStore.save(water)
        savedWater = water
    }

    private func scheduleSoon() {
        guard !stopped else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: self?.timing.batchWindow ?? .seconds(1))
            guard !Task.isCancelled, let self, !self.stopped else { return }
            await self.syncNow()
        }
    }

    private func set(_ new: SyncStatus) {
        guard status != new else { return }
        status = new
        onStatusChange?(new)
    }

    // MARK: One pass

    /// Writes what is waiting, then reads what arrived. Returns the state it ended in.
    @discardableResult
    public func syncNow() async -> SyncStatus {
        guard !stopped else { return status }
        if let current {
            // A pass is running: ask for one more after it, and wait for the whole run so the caller sees its result.
            again = true
            await current.value
            return status
        }
        let run = Task { @MainActor in
            repeat {
                again = false
                await pass()
            } while again && !stopped && !Task.isCancelled
        }
        current = run
        await run.value
        current = nil
        return status
    }

    private func pass() async {
        if isLocked() {
            onPeerDevicesChange?([:])
            return set(.paused)
        }
        guard await Self.rootExists(at: layout.root.path) else { return set(.folderMissing) }
        do {
            try Task.checkCancellation()
            guard let opened = try await openGroup() else { return }
            try await switchEpochIfNeeded(opened)
            let current = group ?? opened
            try await adoptClipsOfMacsThatLeft()
            guard try await recoverOwnLogIfNeeded(current) else { return set(.waitingForFolder) }
            try Task.checkCancellation()
            try await write(current)
            try Task.checkCancellation()
            await writeAppCatalogIfChanged(current)
            try await compactIfNeeded(current)
            try Task.checkCancellation()
            try await read(current)
        } catch is CancellationError {
            return
        } catch let error as SyncError {
            set(.refused(SyncCopy.refusal(error, device: deviceKind)))
        } catch {
            if Self.isStorageFullError(error) {
                set(.storageFull(isICloud: folderProbe.isICloud(layout.root)))
            } else {
                set(.refused("Sync stopped: \(error.localizedDescription)"))
            }
        }
    }

    private func openGroup() async throws -> SyncGroup? {
        let joined = water.vaultFloor.flatMap { Data(hexString: $0.vaultID) }
        switch try await Self.openGroupOffMain(layout: layout, keyStore: keyStore, preferring: joined) {
        case .empty:
            set(.waitingForFolder)
            return nil
        case let .needsKey(vault):
            try water.check(vaultID: vault.vaultID, epoch: vault.epoch)
            set(.needsKey)
            return nil
        case let .ready(found):
            try water.admit(vaultID: found.vault.vaultID, epoch: found.epoch)
            saveWater()
            return found
        }
    }

    /// The first time this Mac sees the group, and again after a new epoch (Reset Sync on another Mac): announce this
    /// Mac
    /// under the key, and write the whole history under it, because the others read only what is written under their
    /// key. A Mac that is already announced writes nothing again, so a restart never re-stamps (and so never overrides)
    /// an edit another Mac made meanwhile.
    private func switchEpochIfNeeded(_ found: SyncGroup) async throws {
        let announced = found.devices.contains { $0.deviceID == identity.deviceID }
        let epochChanged = group.map { $0.epoch != found.epoch } ?? false
        if announced, !epochChanged {
            group = found
            publishPeerDevices(found)
            await sendUnstampedOnce()
            return
        }
        try SyncGroupManager.writeDeviceRecord(
            layout: layout, vault: found.vault, key: found.key, identity: identity, now: now()
        )
        if epochChanged {
            water.resetMarks()
            saveWater()
            ownLogRecovered = false
        }
        if !announced || epochChanged { _ = try await storage.restampForSync(.notFrom(deviceID: identity.deviceID)) }
        water.sentUnstampedHistory = true
        saveWater()
        let updated = try SyncGroupManager.openGroup(layout: layout, keyStore: keyStore) ?? found
        group = updated
        publishPeerDevices(updated)
    }

    private func publishPeerDevices(_ current: SyncGroup) {
        let names: [String: String] = Dictionary(
            current.devices.compactMap { record in
                guard record.deviceID != identity.deviceID else { return nil }
                let trimmed = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : (record.deviceID, trimmed)
            },
            uniquingKeysWith: { _, latest in latest }
        )
        onPeerDevicesChange?(names)
    }

    /// A device announced before turn-on stamped its history (ADR 0056) never sent what it held from before. Once per
    /// store (the high-water record remembers it), whatever still carries no stamp goes out. Only once: a clip copied
    /// later during Pause Sync stays on this device. A failure is logged and tried again on the next pass; it never
    /// stops the exchange.
    private func sendUnstampedOnce() async {
        guard water.sentUnstampedHistory != true else { return }
        do {
            let stamped = try await storage.restampForSync(.unstamped)
            water.sentUnstampedHistory = true
            saveWater()
            if stamped >
                0 { logger.info("Sent \(stamped, privacy: .public) clips and collections that were never sent") }
        } catch {
            logger.error("The unsent history could not be marked: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A Mac that used Leave Sync takes its folder, and so its log, with it, but its clips are still here: this Mac
    /// takes them over so that the Macs that join later get them. Only a Mac that says it left counts (its `left`
    /// marker) and whose folder is gone: a folder that has not finished downloading says nothing. The mark kept for
    /// that Mac goes, so one that comes back starts afresh.
    private func adoptClipsOfMacsThatLeft() async throws {
        let present = Set(layout.deviceIDs())
        let gone = Set(water.marks.keys).intersection(layout.leftDeviceIDs()).subtracting(present)
        guard !gone.isEmpty else { return }
        try await storage.adoptClips(fromDevices: gone)
        for device in gone {
            water.forget(device)
        }
        saveWater()
    }

    // MARK: Writing

    /// Finds where this Mac's own log ends, so the next segment chains from it. Returns false while the last file
    /// cannot be read yet (iCloud has it as a placeholder): writing now would chain from nothing and every other Mac
    /// would refuse the log. A file that is damaged is a refusal; one from an older epoch starts the new chain.
    private func recoverOwnLogIfNeeded(_ found: SyncGroup) async throws -> Bool {
        guard !ownLogRecovered else { return true }
        guard let recovered = try await Self.recoverOwnLogOffMain(
            layout: layout, deviceID: identity.deviceID, found: found, isReadable: isReadable
        ) else { return false }
        if let last = recovered { ownLast = last }
        ownLogRecovered = true
        return true
    }

    nonisolated static func sequenceRange(of name: String) -> (first: UInt64, last: UInt64)? {
        let parts = name.replacingOccurrences(of: ".pestolog", with: "").split(separator: "-")
        guard parts.count == 2, let first = UInt64(parts[0]), let last = UInt64(parts[1]) else { return nil }
        return (first, last)
    }

    func write(_ found: SyncGroup, snapshot: Bool = false) async throws {
        var wrote = false
        var drained = snapshot
        for _ in 0..<(snapshot ? Int.max : timing.batchesPerPass) {
            try Task.checkCancellation()
            let outbox = try await storage.buildOutbox(
                includeSensitive: includeSensitive(), syncKey: found.key, limit: snapshot ? 500 : 200
            )
            guard !outbox.records.isEmpty else {
                if !outbox.settled.isEmpty { try await storage.commitOutbox(outbox) }
                drained = true
                break
            }
            let writeContext = WriteContext(
                found: found, layout: layout, identity: identity, folderProbe: folderProbe, now: now
            )
            ownLast = try await Self.writeSegmentOffMain(
                outbox: outbox,
                context: writeContext,
                ownLast: ownLast,
                snapshot: snapshot
            )
            try await storage.commitOutbox(outbox)
            wrote = true
        }
        if wrote {
            let writeContext = WriteContext(
                found: found, layout: layout, identity: identity, folderProbe: folderProbe, now: now
            )
            try await Self.writeHeadOffMain(
                context: writeContext,
                ownLast: ownLast,
                cursors: water.marks.mapValues(\.sequence)
            )
        }
        if !drained { again = true }
    }

    func writeBlobs(_ blobs: [String: Data], _ found: SyncGroup) throws {
        try Self.writeBlobsOffMain(
            blobs, found, layout: layout, deviceID: identity.deviceID, folderProbe: folderProbe
        )
    }

    func writeHead(_ found: SyncGroup) throws {
        let head = SyncHead(
            deviceID: identity.deviceID, epoch: found.epoch, lastSequence: ownLast.sequence,
            lastManifestHash: ownLast.hash, cursors: water.marks.mapValues(\.sequence), writtenAt: now(),
            signerKeyID: identity.keys.publicKeys.keyID
        )
        let url = layout.head(identity.deviceID)
        try folderProbe.willWrite(url)
        try folderProbe.writeData(head.sealed(syncKey: found.key, signedBy: identity.keys), url)
    }

    /// Writes this device's app catalog when its list changed (ADR 0068). A failure is logged and tried again on the
    /// next pass; it never stops the exchange.
    private func writeAppCatalogIfChanged(_ found: SyncGroup) async {
        let sequence = ownLast.sequence
        guard catalogCheckedAt != sequence else { return }
        do {
            let entries = try await storage.syncAppCatalogEntries()
            guard !entries.isEmpty, entries != writtenCatalog else {
                catalogCheckedAt = sequence
                return
            }
            let catalog = SyncAppCatalog(
                deviceID: identity.deviceID, epoch: found.epoch, entries: entries,
                signerKeyID: identity.keys.publicKeys.keyID
            )
            let url = layout.appCatalog(identity.deviceID)
            try folderProbe.willWrite(url)
            try folderProbe.writeData(catalog.sealed(syncKey: found.key, signedBy: identity.keys), url)
            writtenCatalog = entries
            catalogCheckedAt = sequence
        } catch {
            logger.error("The app catalog was not written: \(String(describing: error), privacy: .public)")
        }
    }

    /// Reads the other devices' app catalogs. A missing, damaged or refused one is skipped.
    private func readAppCatalogs(of devices: [String], _ found: SyncGroup) {
        guard let onAppCatalog else { return }
        var entries: [SyncAppCatalog.Entry] = []
        for device in devices {
            let url = layout.appCatalog(device)
            guard let changed = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  readCatalogDates[device] != changed else { continue }
            guard let data = SyncSmallFile.read(url),
                  let catalog = try? SyncAppCatalog.open(
                      data, syncKey: found.key, trust: found.trust, deviceID: device, epoch: found.epoch
                  ) else { continue }
            readCatalogDates[device] = changed
            entries += catalog.entries
        }
        if !entries.isEmpty { onAppCatalog(SyncAppCatalog.bounded(entries)) }
    }

    // MARK: Reading

    private func read(_ found: SyncGroup) async throws {
        let others = found.devices.filter { $0.deviceID != identity.deviceID }.map(\.deviceID)
        var waiting = false
        var received = 0
        var firstFailure: (any Error)?
        for device in others {
            do {
                let outcome = try await readDevice(device, found)
                waiting = waiting || outcome.waiting
                received += outcome.applied
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // One Mac's damaged or refused file must not stop the others from being read.
                firstFailure = firstFailure ?? error
            }
        }
        if received > 0 { lastReceived = now() }
        readAppCatalogs(of: others, found)
        if await hasUploadQuotaError() { return set(.storageFull(isICloud: true)) }
        if let firstFailure { throw firstFailure }
        if waiting { return set(.waitingForFolder) }
        if !others.isEmpty, let since = lastReceived ?? group?.devices.map(\.createdAt).max(),
           now().timeIntervalSince(since) > timing.quietAfter
        {
            return set(.nothingNew(since: since))
        }
        set(.upToDate(now()))
    }

    private func readDevice(_ device: String, _ found: SyncGroup) async throws -> (applied: Int, waiting: Bool) {
        let done = water.mark(for: device)?.sequence ?? 0
        let todo = await Self.pendingSegmentsOffMain(logDirectory: layout.log(device).path, after: done)
        var applied = 0
        for (index, name) in todo.enumerated() {
            try Task.checkCancellation()
            if todo.count > 1 { set(.receiving(done: index, total: todo.count)) }
            let url = layout.log(device).appendingPathComponent(name)
            guard let verified = try await Self.verifySegmentOffMain(
                url: url, found: found, isReadable: isReadable
            ) else {
                // Waiting on iCloud placeholder or wrongEpoch? verifySegmentOffMain distinguishes via enum.
                return (applied, true)
            }
            guard let segment = verified else { continue }
            guard segment.manifest.deviceID == device else { throw SyncError.badSignature }
            switch try water.decide(segment.manifest, currentEpoch: found.epoch) {
            case .duplicate: continue
            case .gap: return (applied, true)
            case .apply: break
            }
            guard let (records, blobs) = try await Self.loadSegmentPayloadsOffMain(
                verified: segment, layout: layout, device: device, found: found, isReadable: isReadable
            ) else { return (applied, true) }
            let summary = try await storage.applySync(records, blob: { blobs[$0] })
            applied += summary.added + summary.updated + summary.removed
            if summary.clockRefused > 0 { throw SyncError.clockFarAhead }
            try water.record(segment.manifest)
            saveWater()
        }
        return (applied, false)
    }

    static func reason(_ error: SyncError) -> String {
        SyncCopy.refusal(error)
    }
}
