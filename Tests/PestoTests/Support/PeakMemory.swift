// SPDX-License-Identifier: MIT
import Darwin
import Foundation
import Synchronization

/// The highest resident size seen while some work runs. The memory a decode or a copy needs is released before the
/// call returns, so it is sampled from a second thread.
enum PeakMemory {
    static func residentBytes() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.resident_size) : 0
    }

    /// The footprint Activity Monitor and `footprint` report: resident plus compressed pages.
    static func footprintBytes() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }

    /// How far the resident size rose above where it started while `work` ran.
    static func growth(during work: () async throws -> Void) async rethrows -> Int {
        let baseline = residentBytes()
        let peak = Mutex(baseline)
        let running = Mutex(true)
        let sampler = Thread {
            while running.withLock({ $0 }) {
                let now = residentBytes()
                peak.withLock { $0 = max($0, now) }
                usleep(500)
            }
        }
        sampler.start()
        defer { running.withLock { $0 = false } }
        try await work()
        return peak.withLock { $0 } - baseline
    }
}
