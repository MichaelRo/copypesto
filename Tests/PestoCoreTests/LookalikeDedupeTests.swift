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

private struct NoTextRecognizer: TextRecognizing {
    func recognize(imageData _: Data) async -> String? {
        nil
    }
}

private final class DecodeCount: Sendable {
    private let calls = Mutex(0)

    var value: Int {
        calls.withLock { $0 }
    }

    func digest(_ data: Data) -> Data? {
        calls.withLock { $0 += 1 }
        return PerceptualHasher.pixelDigest(imageData: data)
    }
}

/// One window: a sidebar, a title bar and lines of "words". `edited` changes a few words on one line. 5K only where
/// the case is about 5K, so the other tests do not load the machine under the timing tests beside them.
private struct WindowShot {
    var edited = false
    var interlaced = false
    var dotsPerInch = 72
    var type = UTType.png
    var scale = 4

    func data() throws -> Data {
        let width = 5120 / scale
        let height = 2880 / scale
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        func fill(_ gray: CGFloat, _ rect: CGRect) {
            context.setFillColor(CGColor(srgbRed: gray, green: gray, blue: gray, alpha: 1))
            context.fill(rect.applying(CGAffineTransform(scaleX: 1 / CGFloat(scale), y: 1 / CGFloat(scale))))
        }
        fill(0.96, CGRect(x: 0, y: 0, width: 5120, height: 2880))
        fill(0.3, CGRect(x: 0, y: 0, width: 900, height: 2880))
        fill(0.7, CGRect(x: 900, y: 2760, width: 4220, height: 120))
        for line in 0..<40 {
            for word in 0..<12 {
                let length = 120 + (line * 37 + word * 53) % 140
                fill(0.15, CGRect(x: 1000 + word * 320, y: 2680 - line * 64, width: length, height: 26))
            }
        }
        if edited {
            fill(0.96, CGRect(x: 1960, y: 1400, width: 640, height: 26))
            fill(0.15, CGRect(x: 1960, y: 1400, width: 90, height: 26))
            fill(0.15, CGRect(x: 2090, y: 1400, width: 300, height: 26))
        }
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)
        )
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dotsPerInch, kCGImagePropertyDPIHeight: dotsPerInch,
            kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGInterlaceType: interlaced ? 1 : 0]
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
        return output as Data
    }

    func capture() throws -> PasteboardCapture {
        let payload = try data()
        return PasteboardCapture(
            typeIdentifier: type.identifier,
            payload: payload,
            contentHash: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        )
    }
}

@Suite("Lookalike screenshots", .serialized)
struct LookalikeDedupeTests {
    private func makeService(_ decodes: DecodeCount) throws -> (StorageService, ModelContainer) {
        let container = try ModelContainerSetup.makeInMemory()
        let service = StorageService(modelContainer: container, environment: .testing {
            $0.textRecognizer = NoTextRecognizer()
            $0.pixelDigest = { decodes.digest($0) }
        })
        return (service, container)
    }

    private func cards(_ container: ModelContainer) throws -> [ClipboardItem] {
        try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
    }

    @Test("a lookalike but different 5K screenshot is a new card, and no picture is decoded to tell")
    func ingest_lookalikeButDifferent_isStoredWithoutDecoding() async throws {
        let first = try WindowShot(scale: 1).capture()
        let second = try WindowShot(edited: true, scale: 1).capture()
        let firstHash = try #require(PerceptualHasher.hash(imageData: first.payload))
        let secondHash = try #require(PerceptualHasher.hash(imageData: second.payload))
        let distance = try #require(PerceptualHasher.hammingDistance(firstHash, secondHash))
        #expect(distance <= PerceptualHasher.similarityThreshold, "the pair must be nominated for this test to count")
        let decodes = DecodeCount()
        let (service, container) = try makeService(decodes)

        try await service.ingest(first)
        try await service.ingest(second)
        await service.waitForBackgroundWork()

        #expect(try cards(container).count == 2)
        #expect(decodes.value == 0)
    }

    @Test("the same pixels in a PNG with other metadata are still one card")
    func ingest_samePixelsOtherMetadata_isOneCard() async throws {
        let first = try WindowShot().capture()
        let second = try WindowShot(dotsPerInch: 144).capture()
        #expect(first.payload != second.payload)
        let (service, container) = try makeService(DecodeCount())

        try await service.ingest(first)
        try await service.ingest(second)
        await service.waitForBackgroundWork()

        #expect(try cards(container).count == 1)
    }

    @Test(
        "the same pixels in an encoding that is read differently are still one card",
        arguments: [WindowShot(interlaced: true), WindowShot(type: .tiff)]
    )
    private func ingest_samePixelsOtherLayout_isOneCard(other: WindowShot) async throws {
        let (service, container) = try makeService(DecodeCount())

        try await service.ingest(WindowShot().capture())
        try await service.ingest(other.capture())
        await service.waitForBackgroundWork()

        #expect(try cards(container).count == 1)
    }

    @Test("a picture saved before it had a fingerprint is compared by its pixels, as before")
    func ingest_nomineeWithoutFingerprint_isDecoded() async throws {
        let decodes = DecodeCount()
        let (service, container) = try makeService(decodes)
        try await service.ingest(WindowShot().capture())
        await service.waitForBackgroundWork()
        let context = ModelContext(container)
        let stored = try #require(try context.fetch(FetchDescriptor<ClipboardItem>()).first)
        stored.metadataCiphertext = nil
        stored.metadataNonce = nil
        try context.save()

        try await service.ingest(WindowShot(edited: true).capture())
        await service.waitForBackgroundWork()

        #expect(try cards(container).count == 2)
        #expect(decodes.value == 2, "the new picture and the one it is compared with")
    }
}
