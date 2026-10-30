// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import SwiftData
import XCTest
@testable import Pesto

/// How long writing a backup takes and how much memory it needs, over a file-backed store of real ingested clips (text,
/// with a picture for every fortieth). `PESTO_BACKUP_CLIPS` raises the size for a one-off measurement. The restore side
/// is `BackupRestorePerformanceTests`.
final class BackupWritePerformanceTests: XCTestCase {
    private var clipCount: Int {
        ProcessInfo.processInfo.environment["PESTO_BACKUP_CLIPS"].flatMap(Int.init) ?? 2000
    }

    func test_writingABackup_isMeasuredAndBounded() async throws {
        try XCTSkipIf(RunEnvironment.isCI, "timings are only meaningful on a developer Mac")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-backup-perf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try ModelContainerSetup.openClips(storeURL: directory.appendingPathComponent("clips.store")
        )
        let service = StorageService(modelContainer: container)
        for index in 0..<clipCount {
            if index % 40 == 39 {
                let picture = PictureFixtures.png(width: 640 - index % 40, height: 400, fill: .noise)
                try await service.ingest(ClipKindFixtures.capture("public.png", payload: picture))
            } else {
                try await service.ingest(ClipKindFixtures.text(
                    "Backed up clip \(index): the quick brown fox jumps over the lazy dog, again and again."
                ))
            }
        }

        let key = BackupKey.generate()
        let header = try BackupFile.makeHeader(key: key, passphrase: "p", iterations: 1000)
        var seconds: [Double] = []
        var growthMB = 0.0
        var perRun: [Double] = []
        var fileMB = 0.0
        for run in 0..<3 {
            let file = directory.appendingPathComponent("backup-\(run).pestobackup")
            let writer = try BackupFile.StreamingWriter(url: file, key: key, header: header)
            let clock = ContinuousClock()
            let start = clock.now
            let growth = try await PeakMemory.growth {
                _ = try await service.streamBackupRecords(includeSensitive: false, sink: { try writer.append($0) })
            }
            _ = try writer.finish(origin: BackupOrigin(sequence: 1, deviceID: "perf", createdAt: .now))
            seconds.append(PerfReport.milliseconds(clock.now - start) / 1000)
            growthMB = max(growthMB, Double(growth) / 1_048_576)
            perRun.append(Double(growth) / 1_048_576)
            fileMB = Double((try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0) /
                1_048_576
        }
        let median = seconds.sorted()[1]
        PerfReport.emit(String(
            format: "backup write of %d clips: median %.2f s (%.0f clips/s), file %.1f MB, "
                + "peak memory growth %.0f MB (runs: %@)",
            clipCount, median, Double(clipCount) / median, fileMB, growthMB,
            perRun.map { String(format: "%.0f", $0) }.joined(separator: ", ")
        ))
        // About 4 KB a clip, measured at 2,000, 8,000 and 20,000: SQLite's page cache while the store is read, not
        // clips
        // held by the storage actor (a context per page changed nothing). A leak of the clips themselves would be 10x.
        let allowed = 20 + Double(clipCount) * 0.006
        XCTAssertLessThan(growthMB, allowed, "writing a backup grew memory by \(growthMB) MB; allowed \(allowed) MB")
    }
}
