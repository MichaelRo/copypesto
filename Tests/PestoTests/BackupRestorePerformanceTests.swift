// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import XCTest
@testable import Pesto
@testable import PestoCore

/// How long restoring a large backup takes. A file-backed store, because an in-memory one costs differently
/// (it keeps a blob several times). `PESTO_RESTORE_CLIPS` raises the size for a one-off measurement; the default keeps
/// the gate fast.
final class BackupRestorePerformanceTests: XCTestCase {
    private var clipCount: Int {
        ProcessInfo.processInfo.environment["PESTO_RESTORE_CLIPS"].flatMap(Int.init) ?? 2000
    }

    private func writeBackup(clips: Int, to url: URL, key: BackupKey) throws {
        let header = try BackupFile.makeHeader(key: key, passphrase: "p", iterations: 1000)
        let writer = try BackupFile.StreamingWriter(url: url, key: key, header: header)
        for index in 0..<clips {
            let payload = Data("Restored clip \(index): the quick brown fox jumps over the lazy dog.".utf8)
            let metadata = BackupItemMetadata(
                id: UUID(), timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
                typeRaw: ClipboardType.text.rawValue, mimeType: "public.utf8-plain-text",
                plainHash: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined(),
                sourceBundleID: "com.apple.Notes", sourceAppName: "Notes"
            )
            try writer.append(.item(metadata, payload: payload))
        }
        _ = try writer.finish(origin: BackupOrigin(sequence: 1, deviceID: "perf", createdAt: .now))
    }

    func test_restoringALargeBackup_isMeasured() async throws {
        try XCTSkipIf(RunEnvironment.isCI, "timings are only meaningful on a developer Mac")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-restore-perf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = BackupKey.generate()
        let file = directory.appendingPathComponent("backup.pestobackup")
        try writeBackup(clips: clipCount, to: file, key: key)
        let container = try ModelContainerSetup.openSynced(
            cloudKitEnabled: false, storeURL: directory.appendingPathComponent("clips.store")
        )
        let service = StorageService(modelContainer: container)

        let clock = ContinuousClock()
        var summary = BackupRestoreSummary()
        let elapsed = try await clock.measure {
            let verified = try BackupFile.verify(url: file, credential: .recoveryKey(key))
            summary = try await service.restore(verified)
        }

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let rate = Double(clipCount) / seconds
        add(
            XCTAttachment(string: "restored \(summary.restored) of \(clipCount) clips in \(seconds) s: \(rate) clips/s")
        )
        XCTAssertEqual(summary.restored, clipCount)
    }
}
