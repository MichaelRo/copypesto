// SPDX-License-Identifier: MIT
import Darwin
import Foundation
import PestoCore
import SwiftData
import XCTest
@testable import Pesto

/// The grid's `@Query` loads every column of every item. This measures what that costs in resident memory, for items
/// as the app writes them now: icons resolve by bundle ID and link preview images live in their own store.
final class HistoryMemoryTests: XCTestCase {
    private func residentBytes() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.resident_size) : 0
    }

    @MainActor
    func test_fetchingAllOf5000Items_staysWithinTheMemoryBudget() throws {
        try fetchAll(count: 5000, budgetMB: 40)
    }

    /// The history's maximum (`RetentionChoices.itemCounts`): the cost grows with the count, so the budget scales with
    /// it.
    @MainActor
    func test_fetchingAllOf10000Items_staysWithinTheMemoryBudget() throws {
        try fetchAll(count: 10_000, budgetMB: 80)
    }

    @MainActor
    private func fetchAll(count: Int, budgetMB: Double) throws {
        try XCTSkipIf(RunEnvironment.isCI, "resident-memory deltas are only meaningful on a developer Mac")
        let container = try ModelContainerSetup.makeInMemory()
        let context = ModelContext(container)
        for index in 0..<count {
            let item = ClipboardItem(
                type: index % 4 == 0 ? .url : .text,
                previewText: "item \(index)",
                contentHash: "h-\(index)",
                byteSize: 10,
                deviceID: "mem",
                sequenceNumber: Int64(index)
            )
            item.sourceBundleID = "com.apple.finder"
            item.embeddingData = Data(repeating: 1, count: 2048)
            context.insert(item)
        }
        try context.save()

        let before = residentBytes()
        let fetched = try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
        let after = residentBytes()
        let deltaMB = Double(after - before) / 1_048_576
        PerfReport.emit("history fetch of \(fetched.count) items: +\(String(format: "%.1f", deltaMB)) MB resident")

        XCTAssertLessThan(
            deltaMB,
            budgetMB,
            "loading \(fetched.count) items cost \(deltaMB) MB; the steady-state budget is 150 MB"
        )
    }
}
