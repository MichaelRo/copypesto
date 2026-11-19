// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import PestoCore
import SwiftData

struct PeerCommand: Decodable {
    let op: String
    var key: String?
    var text: String?
    var title: String?
    var collection: String?
    var copiedAt: Double?
    var pastedAt: Double?
    var path: String?
}

struct PeerResponse: Encodable {
    var ok = true
    var error: String?
    var status: String?
    var flow: String?
    var isEnabled: Bool?
    var recoveryKey: String?
    var words: [String]?
    var pendingJoinWords: [String]?
    var clips: [String]?
    var collectionOrder: [String]?
    var restored: Int?
    var removedByTombstone: Int?
}

private struct FileSecretStore: SecretStoring {
    let directory: URL

    private func fileURL(service: String, account: String) -> URL {
        let name = Data("\(service)|\(account)".utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent(name)
    }

    func read(service: String, account: String) throws -> Data? {
        let url = fileURL(service: service, account: account)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func write(_ data: Data, service: String, account: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL(service: service, account: account), options: .atomic)
    }

    func delete(service: String, account: String) {
        try? FileManager.default.removeItem(at: fileURL(service: service, account: account))
    }
}

private func parseArg(_ flag: String, in args: [String]) -> String? {
    guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
    return args[idx + 1]
}

private func describeStatus(_ status: SyncStatus) -> String {
    switch status {
    case .off: "off"
    case .paused: "paused"
    case .upToDate: "upToDate"
    case .receiving: "receiving"
    case .waitingForFolder: "waitingForFolder"
    case .folderMissing: "folderMissing"
    case .nothingNew: "nothingNew"
    case .needsKey: "needsKey"
    case let .storageFull(isICloud): "storageFull:\(isICloud ? "icloud" : "folder")"
    case let .refused(reason): "refused:\(reason)"
    }
}

private func describeFlow(_ flow: SyncFlow) -> String {
    switch flow {
    case .idle: "idle"
    case .setUp: "setUp"
    case .joinOffer: "joinOffer"
    case .iCloudKeychainOff: "iCloudKeychainOff"
    case .needsKey: "needsKey"
    case .pairing: "pairing"
    case .enterRecoveryKey: "enterRecoveryKey"
    case .recoveryKey: "recoveryKey"
    case let .failed(reason): "failed:\(reason)"
    }
}

@MainActor
final class PeerHost {
    let container: ModelContainer
    let storage: StorageService
    let controller: SyncController
    let deviceID: String
    let storeDir: URL

    @MainActor
    init(storeDir: URL, syncDir: URL, deviceID: String, deviceName: String) throws {
        self.storeDir = storeDir
        self.deviceID = deviceID
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        let storeURL = storeDir.appendingPathComponent("clips.store")
        container = try ModelContainerSetup.openClips(storeURL: storeURL)

        let encryption = BlobEncryption()
        _ = try encryption.loadOrCreateKey()
        let env = StorageEnvironment.testing {
            $0.sequenceCounter = SequenceCounter(defaults: AppDefaults.store)
            $0.deviceID = { deviceID }
            $0.keyRotator = { try encryption.rotateKey() }
            $0.previewSealer = { data, aad in try encryption.encrypt(data, associatedData: aad) }
        }
        storage = StorageService(modelContainer: container, environment: env)

        let secrets = FileSecretStore(directory: storeDir.appendingPathComponent("secrets", isDirectory: true))
        let highWater = SealedHighWaterStore(url: storeDir.appendingPathComponent("highwater.sealed"))
        var syncEnv = SyncController.Environment(
            container: container,
            storage: storage,
            folder: syncDir,
            keyStore: ThisDeviceSyncKeyStore(secrets: secrets),
            deviceKeys: KeychainDeviceKeyStore(secrets: secrets),
            highWater: highWater,
            defaults: AppDefaults.store,
            deviceID: deviceID,
            deviceName: deviceName
        )
        syncEnv.timing.batchWindow = Duration.milliseconds(50)
        syncEnv.timing.pollInterval = Duration.seconds(30)
        controller = SyncController(syncEnv)
    }

    @MainActor
    func handle(_ cmd: PeerCommand) async -> PeerResponse {
        do {
            if let syncResp = try await handleSyncOp(cmd) { return syncResp }
            if let pairResp = try await handlePairingOp(cmd) { return pairResp }
            if let clipResp = try await handleClipOp(cmd) { return clipResp }
            if let backupResp = try await handleBackupOp(cmd) { return backupResp }
            return PeerResponse(ok: false, error: "unknown op \(cmd.op)")
        } catch {
            return PeerResponse(ok: false, error: error.localizedDescription)
        }
    }

    @MainActor
    private func handleSyncOp(_ cmd: PeerCommand) async throws -> PeerResponse? {
        switch cmd.op {
        case "turnOn":
            await controller.turnOn()
            return baseResponse()
        case "resumeIfEnabled":
            controller.resumeIfEnabled()
            return baseResponse()
        case "syncNow":
            await controller.syncNow()
            return baseResponse()
        case "pause":
            controller.pause()
            return baseResponse()
        case "reset":
            await controller.reset()
            return baseResponse()
        case "leave":
            controller.leave()
            return baseResponse()
        case "quit":
            return baseResponse()
        default:
            return nil
        }
    }

    @MainActor
    private func handlePairingOp(_ cmd: PeerCommand) async throws -> PeerResponse? {
        switch cmd.op {
        case "askAnotherMac":
            controller.askAnotherMac()
            return baseResponse()
        case "refresh":
            controller.refresh()
            var resp = baseResponse()
            resp.pendingJoinWords = controller.pendingJoin?.words
            return resp
        case "allowPending":
            guard let pending = controller.pendingJoin else {
                return PeerResponse(ok: false, error: "no pending join")
            }
            controller.allow(pending)
            return baseResponse()
        case "confirmJoin":
            controller.confirmJoin()
            return baseResponse()
        case "useRecoveryKey":
            await controller.useRecoveryKey(cmd.key ?? "")
            return baseResponse()
        default:
            return nil
        }
    }

    @MainActor
    private func handleClipOp(_ cmd: PeerCommand) async throws -> PeerResponse? {
        switch cmd.op {
        case "copy":
            let text = cmd.text ?? ""
            let payload = Data(text.utf8)
            let hash = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
            let timestamp = cmd.copiedAt.map { Date(timeIntervalSince1970: $0) } ?? .now
            try await storage.ingest(PasteboardCapture(
                typeIdentifier: "public.utf8-plain-text", payload: payload, payloadString: text,
                frontmostBundleID: "com.apple.Notes", timestamp: timestamp, contentHash: hash
            ))
            if let title = cmd.title, let item = try findItem(text: text) {
                item.customTitle = title
                try ModelContext(container).saveOrRollback()
            }
            if let colName = cmd.collection {
                try assignCollection(name: colName, toText: text, copiedAt: cmd.copiedAt)
            }
            return baseResponse()
        case "editTitle":
            guard let item = try findItem(text: cmd.text) else {
                return PeerResponse(ok: false, error: "clip not found")
            }
            item.customTitle = cmd.title
            try ModelContext(container).saveOrRollback()
            return baseResponse()
        case "delete":
            guard let item = try findItem(text: cmd.text) else {
                return PeerResponse(ok: false, error: "clip not found")
            }
            try await storage.deleteItems(ids: [item.id], reason: .user)
            return baseResponse()
        case "notePasted":
            guard let item = try findItem(text: cmd.text) else {
                return PeerResponse(ok: false, error: "clip not found")
            }
            let date = cmd.pastedAt.map { Date(timeIntervalSince1970: $0) } ?? .now
            _ = try await storage.notePasted(id: item.id, at: date)
            return baseResponse()
        default:
            return nil
        }
    }

    @MainActor
    private func handleBackupOp(_ cmd: PeerCommand) async throws -> PeerResponse? {
        switch cmd.op {
        case "exportBackup":
            guard let path = cmd.path else { return PeerResponse(ok: false, error: "missing path") }
            let (records, _) = try await storage.backupRecords(includeSensitive: false)
            let data = try BackupFile.write(
                records: records,
                origin: BackupOrigin(sequence: 1, deviceID: deviceID, createdAt: .now),
                key: BackupKey(symmetricKey: SymmetricKey(size: .bits256)),
                passphrase: "peer-test-passphrase",
                iterations: 1000
            )
            try data.write(to: URL(fileURLWithPath: path))
            return baseResponse()
        case "restoreBackup":
            guard let path = cmd.path else { return PeerResponse(ok: false, error: "missing path") }
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let contents = try BackupFile.read(
                data, credential: BackupCredential.passphrase("peer-test-passphrase")
            )
            let summary = try await storage.restore(contents)
            var resp = baseResponse()
            resp.restored = summary.restored
            resp.removedByTombstone = summary.removedByTombstone
            return resp
        case "state":
            return try stateResponse(collection: cmd.collection)
        default:
            return nil
        }
    }

    @MainActor
    private func findItem(text: String?) throws -> ClipboardItem? {
        try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
            .first(where: { $0.blob?.decryptedText() == text })
    }

    @MainActor
    private func stateResponse(collection: String?) throws -> PeerResponse {
        var resp = baseResponse()
        let context = ModelContext(container)
        let items = try context.fetch(
            FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        )
        resp.clips = items.compactMap { $0.blob?.decryptedText() }
        if let colName = collection,
           let board = try context.fetch(FetchDescriptor<Pinboard>()).first(where: { $0.name == colName })
        {
            let inBoard = items.filter { $0.collectionID == board.id }
            resp.collectionOrder = CollectionOrder.sorted(inBoard).compactMap {
                $0.blob?.decryptedText()
            }
        }
        return resp
    }

    @MainActor
    private func assignCollection(name: String, toText text: String, copiedAt: Double?) throws {
        let context = ModelContext(container)
        let board: Pinboard
        if let existing = try context.fetch(FetchDescriptor<Pinboard>()).first(where: { $0.name == name }) {
            board = existing
        } else {
            let created = Pinboard(name: name, symbolName: "folder", colorHex: "#34C759", sortOrder: 0)
            context.insert(created)
            try context.saveOrRollback()
            board = created
        }
        guard let item = try context.fetch(FetchDescriptor<ClipboardItem>())
            .first(where: { $0.blob?.decryptedText() == text }) else { return }
        item.collectionID = board.id
        item.isPinned = true
        if let copiedAt {
            item.adoptFirstCopy(Date(timeIntervalSince1970: copiedAt))
        }
        try context.saveOrRollback()
    }

    @MainActor
    private func baseResponse() -> PeerResponse {
        var resp = PeerResponse()
        resp.status = describeStatus(controller.status)
        resp.flow = describeFlow(controller.flow)
        resp.isEnabled = controller.isEnabled
        if case let .recoveryKey(key) = controller.flow {
            resp.recoveryKey = key
        }
        if case let .pairing(words, _) = controller.flow {
            resp.words = words
        }
        resp.pendingJoinWords = controller.pendingJoin?.words
        return resp
    }
}

let args = CommandLine.arguments
guard let storePath = parseArg("--store-dir", in: args),
      let syncPath = parseArg("--sync-dir", in: args),
      let deviceID = parseArg("--device-id", in: args),
      let deviceName = parseArg("--device-name", in: args) else
{
    fputs(
        "Usage: SyncPeerTool -UITestMode --store-dir <dir> --sync-dir <dir> --device-id <id> --device-name <name>\n",
        stderr
    )
    exit(2)
}

let host = try await MainActor.run {
    try PeerHost(
        storeDir: URL(fileURLWithPath: storePath, isDirectory: true),
        syncDir: URL(fileURLWithPath: syncPath, isDirectory: true),
        deviceID: deviceID,
        deviceName: deviceName
    )
}

let decoder = JSONDecoder()
let encoder = JSONEncoder()

while let line = await Task.detached(operation: { readLine(strippingNewline: true) }).value {
    if line.isEmpty { continue }
    let data = Data(line.utf8)
    let response: PeerResponse
    do {
        let cmd = try decoder.decode(PeerCommand.self, from: data)
        response = await host.handle(cmd)
        let out = try encoder.encode(response)
        FileHandle.standardOutput.write(out + Data("\n".utf8))
        fflush(stdout)
        if cmd.op == "quit" {
            exit(0)
        }
    } catch {
        let errResp = PeerResponse(ok: false, error: error.localizedDescription)
        if let out = try? encoder.encode(errResp) {
            FileHandle.standardOutput.write(out + Data("\n".utf8))
            fflush(stdout)
        }
    }
}
