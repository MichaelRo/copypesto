// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

/// What one widget snapshot costs to choose over a large history in collections (ADR 0060): every clip has sealed
/// metadata, so each one a collection's order reads is an AES-GCM open. The app rewrites the snapshot a second after
/// every save while a widget is installed. It asserts on a developer Mac and only measures on CI (`CI` or `PESTO_CI`).
@Suite("Widget snapshot performance", .serialized)
@MainActor
struct WidgetSnapshotPerformanceTests {
    private static let clipCount = 5000

    private var isCI: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["PESTO_CI"] != nil || environment["CI"] != nil
    }

    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    private func report(_ line: String) {
        FileHandle.standardError.write(Data("PERF widget-snapshot \(line)\n".utf8))
    }

    /// 5,000 text clips with sealed metadata, every 50th placed by hand, spread round-robin over `collections` plain
    /// collections; the time of the first snapshot over it, with no metadata opened yet.
    private func measure(collections: Int, name: String) throws -> (snapshot: WidgetSnapshot, milliseconds: Double) {
        let container = try ModelContainerSetup.makeInMemory()
        let setup = ModelContext(container)
        let boards = (0..<collections).map { index in
            Pinboard(name: "Collection \(index)", symbolName: "folder", colorHex: "#2F8B4C", sortOrder: index)
        }
        boards.forEach(setup.insert)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for index in 0..<Self.clipCount {
            let text = "clip \(index)"
            let item = ClipboardItem(
                type: .text, previewText: text, contentHash: UUID().uuidString, byteSize: text.utf8.count,
                deviceID: "t", sequenceNumber: Int64(index)
            )
            item.timestamp = start + Double(index)
            item.collectionID = boards[index % boards.count].id
            setup.insert(item)
            item.updateMetadata { $0.copiedAt = start + Double(index) }
            if index % 50 == 0 { item.collectionOrder = index / 50 }
        }
        try setup.saveOrRollback()
        PreviewTextCache.shared.clear()

        var snapshot: WidgetSnapshot?
        let time = try ContinuousClock().measure {
            snapshot = try WidgetSnapshotSelection.snapshot(
                in: ModelContext(container), now: .now, theme: .brand, source: { _ in nil }
            )
        }
        report("\(name): \(String(format: "%.1f", milliseconds(time))) ms")
        return try (#require(snapshot), milliseconds(time))
    }

    @Test("5,000 clips in 24 plain collections, each with sealed metadata, are chosen within budget")
    func whenSpreadOverTheMostCollections_thenTheSnapshotStaysCheap() throws {
        let measured = try measure(collections: WidgetSnapshotPolicy.maxCollections, name: "24 collections")

        #expect(measured.snapshot.collections.count == WidgetSnapshotPolicy.maxCollections)
        #expect(measured.snapshot.collections.allSatisfy {
            measured.snapshot.clips(inCollection: $0.id).count == WidgetSnapshotPolicy.maxClips
        })
        if !isCI {
            #expect(measured.milliseconds < 400)
        }
    }

    @Test("5,000 clips in one plain collection open only the newest members' metadata")
    func whenOneCollectionIsHuge_thenOnlyItsNewestMembersAreRead() throws {
        let measured = try measure(collections: 1, name: "1 collection")

        #expect(measured.snapshot.collections.count == 1)
        if !isCI {
            #expect(measured.milliseconds < 50)
        }
    }
}
