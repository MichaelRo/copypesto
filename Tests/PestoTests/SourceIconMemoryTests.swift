// SPDX-License-Identifier: MIT
import Darwin
import Foundation
import Synchronization
import XCTest
@testable import Pesto
@testable import PestoCore

/// Resolving an app's icon used to turn the whole multi-size icon into a TIFF twice (once for the thumbnail, once for
/// its dominant colour): a 64 MB buffer per app, built in a SwiftUI body the first time the shelf shows that app. With
/// a handful of apps in the history that made opening the shelf peak at 410 MB (`docs/perf/budgets-2026-10.md`).
final class SourceIconMemoryTests: XCTestCase {
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

    private func peakGrowth(during work: () -> Void) -> Int {
        let baseline = Self.residentBytes()
        let peak = Mutex(baseline)
        let running = Mutex(true)
        let sampler = Thread {
            while running.withLock({ $0 }) {
                let now = Self.residentBytes()
                peak.withLock { $0 = max($0, now) }
                usleep(300)
            }
        }
        sampler.start()
        work()
        running.withLock { $0 = false }
        return peak.withLock { $0 } - baseline
    }

    @MainActor
    func test_resolvingAppIcons_doesNotBuildHugeBuffers() throws {
        try XCTSkipIf(RunEnvironment.isCI, "resident-memory deltas are only meaningful on a developer Mac")
        let apps = ["com.apple.finder", "com.apple.Safari", "com.apple.Notes", "com.apple.Terminal", "com.apple.mail"]
        var records: [SourceAppRecord] = []

        let growth = peakGrowth {
            records = apps.map { SourceAppResolver.computeRecord(bundleID: $0) }
        }

        add(XCTAttachment(string: "five app icons resolved: peak +\(growth >> 20) MB"))
        XCTAssertLessThan(growth, 24 * 1024 * 1024, "resolving icons grew resident memory by \(growth >> 20) MB")
        for record in records {
            XCTAssertFalse(record.iconData.isEmpty, "\(record.bundleID) has no icon")
            XCTAssertTrue(record.dominantColorHex.hasPrefix("#"), "\(record.bundleID): \(record.dominantColorHex)")
        }
    }
}
