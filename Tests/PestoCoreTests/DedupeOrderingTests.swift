// SPDX-License-Identifier: MIT
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import SwiftData
import Synchronization
import Testing
import UniformTypeIdentifiers
@testable import PestoCore

private final class TestClock: Sendable {
    private let state: Mutex<Date>

    init(_ start: Date) {
        state = Mutex(start)
    }

    var now: Date {
        state.withLock { $0 }
    }

    func set(_ date: Date) {
        state.withLock { $0 = date }
    }
}

/// Copying something that is already in history must bring it to the front, whichever way it is recognised.
@Suite("Re-copying moves a clip to the front", .serialized)
struct DedupeOrderingTests {
    private let container: ModelContainer
    private let service: StorageService

    init() async throws {
        container = try ModelContainerSetup.makeInMemory()
        service = StorageService(modelContainer: container)
    }

    private func newestFirst() throws -> [ClipboardItem] {
        try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(
            \.timestamp,
            order: .reverse
        )]))
    }

    private func text(_ value: String, at time: Date) -> PasteboardCapture {
        PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data(value.utf8), payloadString: value,
            timestamp: time,
            contentHash: SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
        )
    }

    private func png(_ red: Double) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: red, green: 0.3, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 4, y: 4, width: 12, height: 12))
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        try CGImageDestinationAddImage(destination, #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func image(_ data: Data, at time: Date) -> PasteboardCapture {
        PasteboardCapture(
            typeIdentifier: "public.png", payload: data, payloadString: nil, timestamp: time,
            contentHash: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }

    @Test("an identical text copy moves the existing clip to the front")
    func whenSameTextCopiedAgain_thenFront() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = TestClock(start)
        await service.updateClock { clock.now }
        for (index, value) in ["A", "B", "C"].enumerated() {
            clock.set(start.addingTimeInterval(Double(index) * 10))
            try await service.ingest(text(value, at: clock.now))
        }

        clock.set(start.addingTimeInterval(100))
        try await service.ingest(text("A", at: clock.now))

        #expect(try newestFirst().map(\.displayPreviewText) == ["A", "C", "B"])
    }

    @Test("assignCollectionOnlyIfUnfiled files new and unfiled duplicates without moving already-filed clips")
    func whenDefaultPasteCollectionApplied_thenExistingCollectionPreserved() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = TestClock(start)
        await service.updateClock { clock.now }

        let context = ModelContext(container)
        let defaultBoard = Pinboard(name: "Pasted", symbolName: "doc.on.clipboard", colorHex: "#2F8B4C", sortOrder: 0)
        let workBoard = Pinboard(name: "Work", symbolName: "briefcase", colorHex: "#2F8B4C", sortOrder: 1)
        context.insert(defaultBoard)
        context.insert(workBoard)
        try context.save()

        try await service.ingest(text("Unfiled", at: clock.now))
        clock.set(start.addingTimeInterval(10))
        try await service.ingest(text("Filed", at: clock.now), collectionID: workBoard.id)

        clock.set(start.addingTimeInterval(20))
        try await service.ingest(
            text("Fresh", at: clock.now), collectionID: defaultBoard.id, assignCollectionOnlyIfUnfiled: true
        )
        clock.set(start.addingTimeInterval(30))
        try await service.ingest(
            text("Unfiled", at: clock.now), collectionID: defaultBoard.id, assignCollectionOnlyIfUnfiled: true
        )
        clock.set(start.addingTimeInterval(40))
        try await service.ingest(
            text("Filed", at: clock.now), collectionID: defaultBoard.id, assignCollectionOnlyIfUnfiled: true
        )

        let byPreview = try Dictionary(uniqueKeysWithValues: newestFirst()
            .map { ($0.displayPreviewText, $0.collectionID) })
        #expect(byPreview["Fresh"] == defaultBoard.id)
        #expect(byPreview["Unfiled"] == defaultBoard.id)
        #expect(byPreview["Filed"] == workBoard.id)
    }

    @Test("ingest drops deleted or smart collectionIDs and assigns unfiled perceptual image duplicates")
    func whenCollectionDeletedOrSmart_thenIngestFallsBackAndLookalikeRespectsUnfiled() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = TestClock(start)
        await service.updateClock { clock.now }

        let context = ModelContext(container)
        let defaultBoard = Pinboard(name: "Pasted", symbolName: "doc.on.clipboard", colorHex: "#2F8B4C", sortOrder: 0)
        let workBoard = Pinboard(name: "Work", symbolName: "briefcase", colorHex: "#2F8B4C", sortOrder: 1)
        let smartData = try SmartCollectionPredicate.encodeRuleSet(PredicateRuleSet.snippets)
        let smartBoard = Pinboard(
            name: "Snippets", symbolName: "curlybraces", colorHex: "#2F8B4C", sortOrder: 2,
            isSmart: true, smartPredicateData: smartData
        )
        context.insert(defaultBoard)
        context.insert(workBoard)
        context.insert(smartBoard)
        try context.save()

        try await service.ingest(text("BadTarget", at: clock.now), collectionID: UUID())
        clock.set(start.addingTimeInterval(10))
        try await service.ingest(text("SmartTarget", at: clock.now), collectionID: smartBoard.id)

        let unfiledImg = try png(0.2)
        let filedImg = try png(0.8)
        clock.set(start.addingTimeInterval(20))
        try await service.ingest(image(unfiledImg, at: clock.now))
        clock.set(start.addingTimeInterval(30))
        try await service.ingest(image(filedImg, at: clock.now), collectionID: workBoard.id)

        // Re-ingest perceptual matches after 2s echo window with assignCollectionOnlyIfUnfiled = true
        clock.set(start.addingTimeInterval(40))
        try await service.ingest(
            image(unfiledImg, at: clock.now), collectionID: defaultBoard.id, assignCollectionOnlyIfUnfiled: true
        )
        clock.set(start.addingTimeInterval(50))
        try await service.ingest(
            image(filedImg, at: clock.now), collectionID: defaultBoard.id, assignCollectionOnlyIfUnfiled: true
        )

        let items = try newestFirst()
        let bad = try #require(items.first { $0.displayPreviewText == "BadTarget" })
        let smartItem = try #require(items.first { $0.displayPreviewText == "SmartTarget" })
        #expect(bad.collectionID == nil)
        #expect(smartItem.collectionID == nil)

        let imageItems = items.filter { $0.type == .image }
        #expect(imageItems.count == 2)
        let imageCollections = Set(imageItems.compactMap(\.collectionID))
        #expect(imageCollections == Set([defaultBoard.id, workBoard.id]))
    }

    @Test("an identical image copy moves the existing clip to the front")
    func whenSameImageCopiedAgain_thenFront() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = TestClock(start)
        await service.updateClock { clock.now }
        let first = try png(0.9)
        try await service.ingest(image(first, at: start))
        clock.set(start.addingTimeInterval(10))
        try await service.ingest(text("between", at: clock.now))
        clock.set(start.addingTimeInterval(20))
        try await service.ingest(image(first, at: clock.now))

        let order = try newestFirst()
        #expect(order.count == 2)
        #expect(order.first?.type == .image, "the re-copied image is not first")
    }

    @Test("a re-encoded copy of the same picture also moves the existing clip to the front")
    func whenSamePictureDifferentBytes_thenFront() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = TestClock(start)
        await service.updateClock { clock.now }
        try await service.ingest(image(png(0.9), at: start))
        clock.set(start.addingTimeInterval(10))
        try await service.ingest(text("between", at: clock.now))
        clock.set(start.addingTimeInterval(20))
        try await service.ingest(image(png(0.9001), at: clock.now))

        let order = try newestFirst()
        #expect(order.count == 2, "a near-identical picture should not create a second clip")
        #expect(order.first?.type == .image, "the re-copied picture is not first")
    }
}
