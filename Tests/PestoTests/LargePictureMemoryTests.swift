// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import PestoCore
import SwiftData
import XCTest
@testable import Pesto

/// The byte limit on a picture says nothing about what decoding it costs: a flat 400-megapixel PNG is 7 MB and made
/// text recognition peak at 3.9 GB (ADR 0006). These watch the resident size while a picture is read, compared and
/// stored.
final class LargePictureMemoryTests: XCTestCase {
    private static let megabyte = 1_048_576
    private static let budget = 450 * megabyte

    func test_whenTextIsRecognisedInAHugePicture_thenMemoryStaysUnderTheBudget() async throws {
        try XCTSkipIf(RunEnvironment.isCI, "resident-memory deltas are only meaningful on a developer Mac")
        let picture = PictureFixtures.png(width: 12_000, height: 12_000)

        let growth = await PeakMemory.growth { _ = await OCRService().recognize(imageData: picture) }

        add(XCTAttachment(string: "144 MP picture, \(picture.count / Self.megabyte) MB file: OCR +\(growth >> 20) MB"))
        XCTAssertLessThan(growth, Self.budget, "recognising text grew resident memory by \(growth >> 20) MB")
    }

    func test_whenASixKPictureIsCompared_thenItStillGetsADigest() {
        let picture = PictureFixtures.png(width: 6016, height: 3384)

        XCTAssertNotNil(
            PerceptualHasher.pixelDigest(imageData: picture),
            "a full 6K screenshot is compared pixel by pixel"
        )
    }

    func test_whenAPictureIsOverTheDecodeLimit_thenItIsNeverComparedPixelByPixel() {
        let picture = PictureFixtures.png(width: 7000, height: 6000)

        XCTAssertNil(PerceptualHasher.pixelDigest(imageData: picture), "42 MP is over the pixel limit")
    }

    func test_whenAPictureNearTheByteLimitIsStored_thenMemoryStaysUnderTheBudget() async throws {
        try XCTSkipIf(RunEnvironment.isCI, "resident-memory deltas are only meaningful on a developer Mac")
        let picture = PictureFixtures.png(width: 6600, height: 4500, fill: .noise)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("large-picture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // An in-memory store keeps the blob several times over and measured 570 MB for this picture; the real store
        // writes it to a file next to the database.
        let container = try ModelContainerSetup.openSynced(
            cloudKitEnabled: false, storeURL: folder.appendingPathComponent("clips.store")
        )
        let service = StorageService(modelContainer: container)
        let capture = PasteboardCapture(
            typeIdentifier: "public.png", payload: picture, timestamp: .now,
            contentHash: SHA256.hash(data: picture).map { String(format: "%02x", $0) }.joined()
        )

        let growth = try await PeakMemory.growth { try await service.ingest(capture) }

        add(XCTAttachment(string: "\(picture.count / Self.megabyte) MB picture: ingest +\(growth >> 20) MB"))
        XCTAssertLessThan(growth, Self.budget, "storing the picture grew resident memory by \(growth >> 20) MB")
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<ClipboardItem>()), 1)
    }
}
