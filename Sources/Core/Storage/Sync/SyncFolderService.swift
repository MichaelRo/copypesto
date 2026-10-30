// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

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

        public init() {}
    }

    private let container: ModelContainer
    let storage: StorageService
    let layout: SyncFolderLayout
    let identity: SyncIdentity
    private let keyStore: SyncKeyStoring
    private let highWaterStore: SyncHighWaterStoring
    let includeSensitive: @MainActor () -> Bool
    private let isLocked: @MainActor () -> Bool
    let now: @Sendable () -> Date
    let timing: Timing

    public private(set) var status: SyncStatus = .off
    public var onStatusChange: (@MainActor (SyncStatus) -> Void)?

    private var group: SyncGroup?
    private var water: SyncHighWater
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

    public init(
        container: ModelContainer, storage: StorageService, layout: SyncFolderLayout, identity: SyncIdentity,
        keyStore: SyncKeyStoring, highWater: SyncHighWaterStoring, timing: Timing = Timing(),
        includeSensitive: @escaping @MainActor () -> Bool = { false },
        isLocked: @escaping @MainActor () -> Bool = { false },
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.container = container
        self.storage = storage
        self.layout = layout
        self.identity = identity
        self.keyStore = keyStore
        highWaterStore = highWater
        water = highWater.load()
        self.timing = timing
        self.includeSensitive = includeSensitive
        self.isLocked = isLocked
        self.now = now
    }

    // MARK: Running

    public func start() {
        guard loop == nil else { return }
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

    public func stop() {
        loop?.cancel()
        pending?.cancel()
        loop = nil
        pending = nil
        watcher?.stop()
        watcher = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        set(.off)
    }

    private func scheduleSoon() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: self?.timing.batchWindow ?? .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.syncNow()
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
            } while again
        }
        current = run
        await run.value
        current = nil
        return status
    }

    private func pass() async {
        if isLocked() { return set(.paused) }
        guard FileManager.default.fileExists(atPath: layout.root.path) else { return set(.folderMissing) }
        do {
            guard let opened = try openGroup() else { return }
            try await switchEpochIfNeeded(opened)
            let current = group ?? opened
            try recoverOwnLogIfNeeded(current)
            try await write(current)
            try await compactIfNeeded(current)
            try await read(current)
        } catch let error as SyncError {
            set(.refused(Self.reason(error)))
        } catch {
            set(.refused("Sync stopped: \(error.localizedDescription)"))
        }
    }

    private func openGroup() throws -> SyncGroup? {
        switch try SyncGroupManager.open(layout: layout, keyStore: keyStore) {
        case .empty:
            set(.waitingForFolder)
            return nil
        case .needsKey:
            set(.needsKey)
            return nil
        case let .ready(found):
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
            return
        }
        try SyncGroupManager.writeDeviceRecord(
            layout: layout, vault: found.vault, key: found.key, identity: identity, now: now()
        )
        if epochChanged {
            water = SyncHighWater()
            highWaterStore.save(water)
            ownLogRecovered = false
        }
        if !announced || epochChanged { _ = try await storage.restampForSync() }
        group = try SyncGroupManager.openGroup(layout: layout, keyStore: keyStore) ?? found
    }

    // MARK: Writing

    private func recoverOwnLogIfNeeded(_ found: SyncGroup) throws {
        guard !ownLogRecovered else { return }
        ownLogRecovered = true
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: layout.log(identity.deviceID).path)) ?? [])
            .filter { $0.hasSuffix(".pestolog") }.sorted()
        guard let last = names.last, let range = Self.sequenceRange(of: last) else { return }
        let url = layout.log(identity.deviceID).appendingPathComponent(last)
        var hash = SyncManifest.zeroHash
        if let data = try? Data(contentsOf: url), let verified = try? SyncSegmentReader.verify(
            data, syncKey: found.key, trust: found.trust, vaultID: found.vault.vaultID, epoch: found.epoch
        ) {
            hash = (try? verified.manifest.hash()) ?? hash
        }
        ownLast = (range.last, hash)
    }

    static func sequenceRange(of name: String) -> (first: UInt64, last: UInt64)? {
        let parts = name.replacingOccurrences(of: ".pestolog", with: "").split(separator: "-")
        guard parts.count == 2, let first = UInt64(parts[0]), let last = UInt64(parts[1]) else { return nil }
        return (first, last)
    }

    func write(_ found: SyncGroup, snapshot: Bool = false) async throws {
        var wrote = false
        for _ in 0..<(snapshot ? Int.max : 20) {
            let outbox = try await storage.buildOutbox(
                includeSensitive: includeSensitive(), syncKey: found.key, limit: snapshot ? 500 : 200
            )
            guard !outbox.records.isEmpty else {
                if !outbox.settled.isEmpty { try await storage.commitOutbox(outbox) }
                break
            }
            try writeBlobs(outbox.blobs, found)
            let first = ownLast.sequence + 1
            let last = first + UInt64(outbox.records.count) - 1
            let url = layout.segment(identity.deviceID, first: first, last: last)
            try FileManager.default.createDirectory(
                at: layout.log(identity.deviceID),
                withIntermediateDirectories: true
            )
            let writer = try SyncSegmentWriter(partialURL: url.appendingPathExtension("partial"), context: .init(
                syncKey: found.key, vaultID: found.vault.vaultID, epoch: found.epoch, deviceID: identity.deviceID,
                device: identity.keys, previousManifestHash: ownLast.hash, isSnapshot: snapshot
            ))
            do {
                for (offset, record) in outbox.records.enumerated() {
                    var numbered = record
                    numbered.sequence = first + UInt64(offset)
                    try writer.append(numbered)
                }
                let manifest = try writer.finish(to: url, now: now())
                ownLast = try (last, manifest.hash())
            } catch {
                writer.abandon()
                throw error
            }
            try await storage.commitOutbox(outbox)
            wrote = true
        }
        if wrote { try writeHead(found) }
    }

    func writeBlobs(_ blobs: [String: Data], _ found: SyncGroup) throws {
        guard !blobs.isEmpty else { return }
        try FileManager.default.createDirectory(at: layout.blobs(identity.deviceID), withIntermediateDirectories: true)
        for (name, payload) in blobs {
            let url = layout.blobs(identity.deviceID).appendingPathComponent(SyncBlobFile.fileName(name))
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            try SyncBlobFile.seal(payload, name: name, syncKey: found.key).write(to: url, options: .atomic)
        }
    }

    func writeHead(_ found: SyncGroup) throws {
        let head = SyncHead(
            deviceID: identity.deviceID, epoch: found.epoch, lastSequence: ownLast.sequence,
            lastManifestHash: ownLast.hash, cursors: water.marks.mapValues(\.sequence), writtenAt: now(),
            signerKeyID: identity.keys.publicKeys.keyID
        )
        try head.sealed(syncKey: found.key, signedBy: identity.keys).write(
            to: layout.head(identity.deviceID),
            options: .atomic
        )
    }

    // MARK: Reading

    private func read(_ found: SyncGroup) async throws {
        let others = found.devices.filter { $0.deviceID != identity.deviceID }.map(\.deviceID)
        var waiting = false
        var received = 0
        for device in others {
            let outcome = try await readDevice(device, found)
            waiting = waiting || outcome.waiting
            received += outcome.applied
        }
        if received > 0 { lastReceived = now() }
        if waiting { return set(.waitingForFolder) }
        if !others.isEmpty, let since = lastReceived ?? group?.devices.map(\.createdAt).max(),
           now().timeIntervalSince(since) > timing.quietAfter
        {
            return set(.nothingNew(since: since))
        }
        set(.upToDate(now()))
    }

    private func readDevice(_ device: String, _ found: SyncGroup) async throws -> (applied: Int, waiting: Bool) {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: layout.log(device).path)) ?? [])
            .filter { $0.hasSuffix(".pestolog") }.sorted()
        let done = water.mark(for: device)?.sequence ?? 0
        let todo = names.filter { (Self.sequenceRange(of: $0)?.last ?? 0) > done }
        var applied = 0
        for (index, name) in todo.enumerated() {
            if todo.count > 1 { set(.receiving(done: index, total: todo.count)) }
            let url = layout.log(device).appendingPathComponent(name)
            guard SyncFileAvailability.isReadable(url) else { return (applied, true) }
            guard let data = try? Data(contentsOf: url) else { return (applied, true) }
            let verified: VerifiedSyncSegment
            do {
                verified = try SyncSegmentReader.verify(
                    data, syncKey: found.key, trust: found.trust, vaultID: found.vault.vaultID, epoch: found.epoch
                )
            } catch SyncError.wrongEpoch {
                continue // from an older epoch: nothing to read
            }
            guard verified.manifest.deviceID == device else { throw SyncError.badSignature }
            switch try water.decide(verified.manifest, currentEpoch: found.epoch) {
            case .duplicate: continue
            case .gap: return (applied, true)
            case .apply: break
            }
            guard let blobs = try blobPayloads(for: verified, device: device, found) else { return (applied, true) }
            let summary = try await storage.applySync(verified.records(), blob: { blobs[$0] })
            applied += summary.added + summary.updated + summary.removed
            if summary.clockRefused > 0 { throw SyncError.clockFarAhead }
            try water.record(verified.manifest)
            highWaterStore.save(water)
        }
        return (applied, false)
    }

    /// The payload files the segment points to, opened; nil when one has not arrived yet.
    private func blobPayloads(
        for segment: VerifiedSyncSegment,
        device: String,
        _ found: SyncGroup
    ) throws
    -> [String: Data]? {
        var out: [String: Data] = [:]
        for record in try segment.records() where record.kind == .item {
            guard let name = try record.decodeMetadata(SyncItemRecord.self).blobName else { continue }
            let url = layout.blobs(device).appendingPathComponent(SyncBlobFile.fileName(name))
            guard SyncFileAvailability.isReadable(url), let data = try? Data(contentsOf: url) else { return nil }
            out[name] = try SyncBlobFile.open(data, name: name, syncKey: found.key)
        }
        return out
    }

    static func reason(_ error: SyncError) -> String {
        switch error {
        case .badSignature: "A file from another Mac did not match its signature. Nothing was changed."
        case .unknownSigner: "A file came from a Mac that is not in this sync group. Nothing was changed."
        case .fork, .rollback, .brokenChain: "Another Mac's log went backwards or was changed. Nothing was changed."
        case .clockFarAhead: "Another Mac's clock is far ahead, so its changes were not applied."
        case .wrongVault, .wrongEpoch, .wrongKey: "The sync group changed. Sync will pick up the new key."
        default: "A file from another Mac is damaged. Nothing was changed."
        }
    }
}
