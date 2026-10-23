// SPDX-License-Identifier: MIT
import Darwin
import Foundation
import PestoCore
import Synchronization
import XCTest
@testable import Pesto

/// Restoring used to read the whole backup file and every decrypted clip into memory. This watches the resident size
/// from a second thread while a large file is opened, because the memory is released again before the call returns.
final class BackupVerifyMemoryTests: XCTestCase {
    private static func residentBytes() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.resident_size) : 0
    }

    /// The highest resident size seen while `work` runs, above where it started.
    private func peakGrowth(during work: () throws -> Void) rethrows -> Int {
        let baseline = Self.residentBytes()
        let peak = Mutex(baseline)
        let running = Mutex(true)
        let sampler = Thread {
            while running.withLock({ $0 }) {
                let now = Self.residentBytes()
                peak.withLock { $0 = max($0, now) }
                usleep(500)
            }
        }
        sampler.start()
        defer { running.withLock { $0 = false } }
        try work()
        return peak.withLock { $0 } - baseline
    }

    func test_verifyingALargeBackup_staysFarBelowTheFileSize() throws {
        try XCTSkipIf(RunEnvironment.isCI, "resident-memory deltas are only meaningful on a developer Mac")
        let key = BackupKey.generate()
        let header = try BackupFile.makeHeader(key: key, passphrase: "p", iterations: 1000)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("large-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try BackupFile.StreamingWriter(url: url, key: key, header: header)
        let clip = Data((0..<(2 * 1024 * 1024)).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        for index in 0..<40 {
            try writer.append(BackupRecord(kind: .item, metadata: Data("{\"id\":\(index)}".utf8), payload: clip))
        }
        let size = try writer.finish(origin: BackupOrigin(sequence: 1, deviceID: "test", createdAt: .now))

        let visited = Mutex(0)
        let streamed = try peakGrowth { _ = try BackupFile.verify(url: url, credential: .recoveryKey(key)) }
        let restoring = try peakGrowth {
            let backup = try BackupFile.verify(url: url, credential: .recoveryKey(key))
            let done = expectation(description: "enumerated")
            Task {
                do {
                    try await backup.forEachItem { _ in visited.withLock { $0 += 1 } }
                } catch {
                    XCTFail("enumerating failed: \(error)")
                }
                done.fulfill()
            }
            wait(for: [done], timeout: 60)
        }
        let whole = try peakGrowth {
            let data = try Data(contentsOf: url)
            _ = try BackupFile.read(data, credential: .recoveryKey(key))
        }

        add(
            XCTAttachment(
                string: "file \(size >> 20) MB: verify +\(streamed >> 20) MB, enumerate +\(restoring >> 20) MB, " +
                    "whole +\(whole >> 20) MB"
            )
        )
        XCTAssertEqual(visited.withLock { $0 }, 40)
        XCTAssertGreaterThan(
            whole,
            size / 2,
            "the control did not show the whole-file cost, so the sampler proves nothing"
        )
        XCTAssertLessThan(
            streamed,
            size / 4,
            "verifying grew resident memory by \(streamed >> 20) MB for a \(size >> 20) MB file"
        )
        XCTAssertLessThan(restoring, size / 4, "enumerating grew resident memory by \(restoring >> 20) MB")
    }
}
