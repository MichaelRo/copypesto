// SPDX-License-Identifier: MIT
import CryptoKit
import Darwin
import Foundation
import SwiftData
import Testing
@testable import PestoCore

private func report(_ line: String) {
    FileHandle.standardError.write(Data("PERF \(line)\n".utf8))
}

private func residentMegabytes() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
}

private func cpuSeconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    func seconds(_ value: timeval) -> Double {
        Double(value.tv_sec) + Double(value.tv_usec) / 1_000_000
    }
    return seconds(usage.ru_utime) + seconds(usage.ru_stime)
}

@Suite("Sync costs: ingest, an idle pass, the first send and the first receive", .serialized)
@MainActor
struct SyncPerformanceTests {
    let layout = SyncFolderLayout(
        root: FileManager.default.temporaryDirectory.appendingPathComponent("pesto-sync-perf-\(UUID().uuidString)")
    )
    let time = TimeBox()
    let clipCount = Int(ProcessInfo.processInfo.environment["PESTO_SYNC_PERF_CLIPS"] ?? "") ?? 2000

    private func ingest(_ storage: StorageService, count: Int, prefix: String) async throws -> Double {
        let started = ContinuousClock.now
        for index in 0..<count {
            let text = "\(prefix) clip number \(index) with some words to make it look like a real copy"
            let payload = Data(text.utf8)
            try await storage.ingest(PasteboardCapture(
                typeIdentifier: "public.utf8-plain-text", payload: payload, payloadString: text,
                frontmostBundleID: "com.apple.Notes", timestamp: .now,
                contentHash: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
            ))
        }
        let elapsed = ContinuousClock.now - started
        return Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
    }

    @Test("a copy costs the same with sync off, and little more with it on")
    func ingestCost() async throws {
        let off = try ModelContainerSetup.makeInMemory()
        let offMs = try await ingest(StorageService(modelContainer: off), count: clipCount, prefix: "off") /
            Double(clipCount)
        let on = try ModelContainerSetup.makeInMemory()
        SyncJournal.enable(for: on, clock: SyncClock(deviceID: "mac-a", defaults: ThrowawayDefaults.make()))
        defer { SyncJournal.disable(for: on) }
        let onMs = try await ingest(StorageService(modelContainer: on), count: clipCount, prefix: "on") /
            Double(clipCount)
        report("sync ingest per clip: off \(offMs) ms, on \(onMs) ms (\(clipCount) clips)")
        #expect(offMs < 50)
        #expect(onMs < 50)
    }

    @Test("an idle pass over a synced history is cheap, and the first send and receive stay within memory")
    func passCosts() async throws {
        let a = try SyncSite(name: "mac-a", layout: layout, time: time)
        let b = try SyncSite(name: "mac-b", layout: layout, time: time)
        let made = try SyncGroupManager.create(
            layout: layout, identity: a.identity, keyStore: a.keyStore, now: time.now
        )
        try b.keyStore.saveSyncKey(made.group.key, vaultID: made.group.vault.vaultID, epoch: 1)
        _ = try await ingest(a.storage, count: clipCount, prefix: "history")

        let memoryBefore = residentMegabytes()
        var cpuMark = cpuSeconds()
        let sendStarted = ContinuousClock.now
        time.advance()
        await a.service.syncNow()
        let sendSeconds = (ContinuousClock.now - sendStarted).seconds
        let sendCPU = cpuSeconds() - cpuMark
        let memoryAfterSend = residentMegabytes()

        cpuMark = cpuSeconds()
        let receiveStarted = ContinuousClock.now
        time.advance()
        await b.service.syncNow()
        let receiveSeconds = (ContinuousClock.now - receiveStarted).seconds
        let receiveCPU = cpuSeconds() - cpuMark
        let memoryAfterReceive = residentMegabytes()
        let received = try b.texts().count
        let sent = try a.texts().count
        report("sync counts: a \(sent), b \(received), expected \(clipCount)")
        #expect(received == clipCount)

        var idle: [Double] = []
        for _ in 0..<5 {
            time.advance()
            let started = ContinuousClock.now
            await a.service.syncNow()
            await b.service.syncNow()
            idle.append((ContinuousClock.now - started).seconds / 2)
        }
        let idleMs = (idle.min() ?? 0) * 1000
        report("""
        sync \(clipCount) clips: send \(sendSeconds) s (cpu \(sendCPU) s, +\(memoryAfterSend - memoryBefore) MB), \
        receive \(receiveSeconds) s (cpu \(receiveCPU) s, +\(memoryAfterReceive - memoryAfterSend) MB), \
        idle pass \(idleMs) ms (every 30 s: \(idleMs / 300) % of one core)
        """)
        #expect(idleMs < 100, "an idle pass every 30 s must stay far under 0.5% CPU")
        #expect(memoryAfterReceive - memoryBefore < 150)
    }
}

private extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
