// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

private struct PeerReply: Decodable {
    let ok: Bool
    let error: String?
    let status: String?
    let flow: String?
    let isEnabled: Bool?
    let recoveryKey: String?
    let words: [String]?
    let pendingJoinWords: [String]?
    let clips: [String]?
    let collectionOrder: [String]?
    let restored: Int?
    let removedByTombstone: Int?
}

private final class PeerProcess: @unchecked Sendable {
    let process: Process
    private let stdinHandle: FileHandle
    private let stdoutHandle: FileHandle
    private var buffer = Data()

    init(
        executable: URL,
        uiTestDir: URL,
        session: String,
        storeDir: URL,
        syncDir: URL,
        deviceID: String,
        deviceName: String
    ) throws {
        process = Process()
        process.executableURL = executable
        process.arguments = [
            "-UITestMode",
            "--store-dir", storeDir.path,
            "--sync-dir", syncDir.path,
            "--device-id", deviceID,
            "--device-name", deviceName
        ]
        var env = ProcessInfo.processInfo.environment
        env["XCTestSessionIdentifier"] = session
        env["PESTO_UITEST_DIR"] = uiTestDir.path
        env["PESTO_UITEST_SESSION"] = session
        process.environment = env

        let inPipe = Pipe()
        let outPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        stdinHandle = inPipe.fileHandleForWriting
        stdoutHandle = outPipe.fileHandleForReading
        try process.run()
    }

    func send(_ payload: [String: Any]) throws -> PeerReply {
        let data = try JSONSerialization.data(withJSONObject: payload)
        stdinHandle.write(data + Data("\n".utf8))
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: 0..<newline)
                buffer.removeSubrange(0...newline)
                return try JSONDecoder().decode(PeerReply.self, from: line)
            }
            let chunk = stdoutHandle.availableData
            if chunk.isEmpty {
                throw NSError(domain: "TwoProcessSyncTests", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "SyncPeerTool closed stdout unexpectedly"
                ])
            }
            buffer.append(chunk)
        }
    }

    func terminateIfRunning() {
        if process.isRunning {
            _ = try? send(["op": "quit"])
            process.waitUntilExit()
        }
    }
}

private final class BundleLocator {}

private func syncPeerToolURL() throws -> URL {
    let bundleDir = Bundle(for: BundleLocator.self).bundleURL.deletingLastPathComponent()
    let candidate1 = bundleDir.appendingPathComponent("SyncPeerTool")
    if FileManager.default.isExecutableFile(atPath: candidate1.path) { return candidate1 }
    let argDir = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0]).deletingLastPathComponent()
    let candidate2 = argDir.appendingPathComponent("SyncPeerTool")
    if FileManager.default.isExecutableFile(atPath: candidate2.path) { return candidate2 }
    throw NSError(domain: "TwoProcessSyncTests", code: 2, userInfo: [
        NSLocalizedDescriptionKey: "SyncPeerTool executable not found next to test bundle at \(bundleDir.path)"
    ])
}

private func pollUntil(
    timeout: Duration = .seconds(15),
    interval: Duration = .milliseconds(100),
    _ check: () async throws -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if try await check() { return }
        try await Task.sleep(for: interval)
    }
    Issue.record("Timed out waiting for two-process sync condition")
}

@Suite("Two-process sync via SyncPeerTool and FSEvents", .serialized, .timeLimit(.minutes(2)))
struct TwoProcessSyncTests {
    @Test("8-word pairing, H1 clip lifecycle + tombstone vs backup + repairs + corrupt refusal, and H5 copiedAt order")
    func whenTwoProcessesSync_thenPairingH1LifecycleAndH5OrderHold() async throws {
        let exe = try syncPeerToolURL()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-2proc-\(UUID().uuidString)", isDirectory: true)
        let syncDir = root.appendingPathComponent("sync", isDirectory: true)
        let storeA = root.appendingPathComponent("store-a", isDirectory: true)
        let storeB = root.appendingPathComponent("store-b", isDirectory: true)
        let uiTestA = root.appendingPathComponent("pesto-uitest-a", isDirectory: true)
        let uiTestB = root.appendingPathComponent("pesto-uitest-b", isDirectory: true)
        try FileManager.default.createDirectory(at: syncDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sessionA = "peer-a-\(UUID().uuidString)"
        let sessionB = "peer-b-\(UUID().uuidString)"
        var peerA: PeerProcess? = try PeerProcess(
            executable: exe, uiTestDir: uiTestA, session: sessionA,
            storeDir: storeA, syncDir: syncDir, deviceID: "peer-a", deviceName: "Peer A"
        )
        let peerB: PeerProcess? = try PeerProcess(
            executable: exe, uiTestDir: uiTestB, session: sessionB,
            storeDir: storeB, syncDir: syncDir, deviceID: "peer-b", deviceName: "Peer B"
        )
        defer {
            peerA?.terminateIfRunning()
            peerB?.terminateIfRunning()
        }

        // 1. 8-word pairing (.pestojoin -> SyncPairingCode.words -> .pestogrant)
        try await pairPeers(peerA: peerA, peerB: peerB)

        // 2. H1 clip lifecycle + tombstone vs backup restore
        let backupPath = root.appendingPathComponent("peer-a.pestobackup").path
        try await verifyH1LifecycleAndBackup(peerA: peerA, peerB: peerB, backupPath: backupPath)

        // 3. H5: copiedAt collection order + non-reordering paste on Peer B
        try await verifyH5OrderAndPaste(peerA: peerA, peerB: peerB)

        // 4. Pause / Resume, Quit / Relaunch, Reset Sync, Corrupt segment Refused, Leave Sync
        let configA = PeerConfig(
            exe: exe, uiTestDir: uiTestA, session: sessionA, storeDir: storeA, syncDir: syncDir
        )
        try await verifyRepairsAndCorruption(configA: configA, peerA: &peerA, peerB: peerB)
    }

    private struct PeerConfig {
        let exe: URL
        let uiTestDir: URL
        let session: String
        let storeDir: URL
        let syncDir: URL
    }

    private func pairPeers(peerA: PeerProcess?, peerB: PeerProcess?) async throws {
        let aTurnOn = try peerA?.send(["op": "turnOn"])
        #expect(aTurnOn?.ok == true)
        #expect(aTurnOn?.recoveryKey != nil)

        let bTurnOn = try peerB?.send(["op": "turnOn"])
        #expect(bTurnOn?.flow == "needsKey")

        let bAsk = try peerB?.send(["op": "askAnotherMac"])
        #expect(bAsk?.flow == "pairing")
        let words = try #require(bAsk?.words)
        #expect(words.count == SyncPairingCode.wordCount)

        try await pollUntil {
            let r = try peerA?.send(["op": "refresh"])
            return r?.pendingJoinWords == words
        }
        let allow = try peerA?.send(["op": "allowPending"])
        #expect(allow?.ok == true)

        try await pollUntil {
            let r = try peerB?.send(["op": "refresh"])
            return r?.flow == "joinOffer"
        }
        let confirm = try peerB?.send(["op": "confirmJoin"])
        #expect(confirm?.isEnabled == true)
    }

    private func verifyH1LifecycleAndBackup(peerA: PeerProcess?, peerB: PeerProcess?, backupPath: String) async throws {
        _ = try peerA?.send(["op": "copy", "text": "hello-h1"])
        try await pollUntil {
            let s = try peerB?.send(["op": "state"])
            return s?.clips?.contains("hello-h1") == true
        }

        let exported = try peerA?.send(["op": "exportBackup", "path": backupPath])
        #expect(exported?.ok == true)

        _ = try peerA?.send(["op": "delete", "text": "hello-h1"])
        try await pollUntil {
            let s = try peerB?.send(["op": "state"])
            return s?.clips?.contains("hello-h1") == false
        }

        let restored = try peerB?.send(["op": "restoreBackup", "path": backupPath])
        #expect(restored?.ok == true)
        #expect((restored?.removedByTombstone ?? 0) >= 0)
        let afterRestore = try peerB?.send(["op": "state"])
        #expect(afterRestore?.clips?.contains("hello-h1") == false)
    }

    private func verifyH5OrderAndPaste(peerA: PeerProcess?, peerB: PeerProcess?) async throws {
        _ = try peerA?.send(["op": "copy", "text": "col-oldest", "collection": "Snippets", "copiedAt": 1000.0])
        _ = try peerA?.send(["op": "copy", "text": "col-middle", "collection": "Snippets", "copiedAt": 2000.0])
        _ = try peerA?.send(["op": "copy", "text": "col-newest", "collection": "Snippets", "copiedAt": 3000.0])

        try await pollUntil {
            let s = try peerB?.send(["op": "state", "collection": "Snippets"])
            return s?.collectionOrder?.count == 3
        }
        let beforePaste = try peerB?.send(["op": "state", "collection": "Snippets"])
        #expect(beforePaste?.collectionOrder == ["col-newest", "col-middle", "col-oldest"])

        _ = try peerB?.send(["op": "notePasted", "text": "col-oldest", "pastedAt": 4000.0])
        let afterPaste = try peerB?.send(["op": "state", "collection": "Snippets"])
        #expect(afterPaste?.clips?.first == "col-oldest")
        #expect(afterPaste?.collectionOrder == ["col-newest", "col-middle", "col-oldest"])
    }

    private func verifyRepairsAndCorruption(
        configA: PeerConfig,
        peerA: inout PeerProcess?,
        peerB: PeerProcess?
    ) async throws {
        let paused = try peerA?.send(["op": "pause"])
        #expect(paused?.isEnabled == false && paused?.status == "off")
        _ = try peerA?.send(["op": "copy", "text": "while-paused"])
        _ = try peerB?.send(["op": "syncNow"])
        #expect(try (peerB?.send(["op": "state"]).clips?.contains("while-paused")) == false)

        let turnOnA = try peerA?.send(["op": "turnOn"])
        if turnOnA?.flow == "joinOffer" {
            _ = try peerA?.send(["op": "confirmJoin"])
        }
        _ = try peerA?.send(["op": "copy", "text": "after-resume"])
        _ = try peerA?.send(["op": "syncNow"])
        try await pollUntil {
            _ = try peerB?.send(["op": "syncNow"])
            let s = try peerB?.send(["op": "state"])
            return s?.clips?.contains("after-resume") == true
        }

        let resetResp = try peerA?.send(["op": "reset"])
        let newKey = try #require(resetResp?.recoveryKey)
        _ = try peerB?.send(["op": "syncNow"])
        let useResp = try peerB?.send(["op": "useRecoveryKey", "key": newKey])
        #expect(useResp?.error == nil, "useRecoveryKey error: \(useResp?.error ?? ""), flow: \(useResp?.flow ?? "")")
        if useResp?.flow == "joinOffer" {
            _ = try peerB?.send(["op": "confirmJoin"])
        }
        _ = try peerA?.send(["op": "copy", "text": "after-reset"])
        _ = try peerA?.send(["op": "syncNow"])
        try await pollUntil {
            _ = try peerB?.send(["op": "syncNow"])
            let s = try peerB?.send(["op": "state"])
            return s?.clips?.contains("after-reset") == true
        }

        _ = try peerA?.send(["op": "copy", "text": "tamper-target"])
        let layout = SyncFolderLayout(root: configA.syncDir)
        let peerAID = try #require(layout.deviceIDs().first { $0.hasPrefix("peer-a") })
        let peerBID = try #require(layout.deviceIDs().first { $0.hasPrefix("peer-b") })
        try await pollUntil {
            _ = try peerA?.send(["op": "syncNow"])
            let files = (try? FileManager.default.contentsOfDirectory(atPath: layout.log(peerAID).path)) ?? []
            return files.contains { $0.hasSuffix(".pestolog") }
        }
        let logFiles = try FileManager.default.contentsOfDirectory(atPath: layout.log(peerAID).path)
            .filter { $0.hasSuffix(".pestolog") }.sorted()
        let latestSeg = try #require(logFiles.last)
        let segURL = layout.log(peerAID).appendingPathComponent(latestSeg)
        var segData = try Data(contentsOf: segURL)
        segData[segData.count / 2] ^= 1
        try segData.write(to: segURL)

        let bAfterTamper = try peerB?.send(["op": "syncNow"])
        #expect(bAfterTamper?.status?.hasPrefix("refused:") == true)

        try verifyRelaunchAndLeave(configA: configA, peerA: &peerA, peerB: peerB, layout: layout, peerBID: peerBID)
    }

    private func verifyRelaunchAndLeave(
        configA: PeerConfig,
        peerA: inout PeerProcess?,
        peerB: PeerProcess?,
        layout: SyncFolderLayout,
        peerBID: String
    ) throws {
        peerA?.terminateIfRunning()
        peerA = nil
        peerA = try PeerProcess(
            executable: configA.exe, uiTestDir: configA.uiTestDir, session: configA.session,
            storeDir: configA.storeDir, syncDir: configA.syncDir, deviceID: "peer-a", deviceName: "Peer A"
        )
        let resumed = try peerA?.send(["op": "resumeIfEnabled"])
        #expect(resumed?.isEnabled == true)

        let left = try peerB?.send(["op": "leave"])
        #expect(left?.isEnabled == false && left?.status == "off")
        #expect(!FileManager.default.fileExists(atPath: layout.device(peerBID).path))
        #expect(try (peerB?.send(["op": "state"]).clips?.contains("after-reset")) == true)
    }
}
