// SPDX-License-Identifier: MIT
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import PestoCore

@Suite("Animated GIF cards", .serialized)
struct AnimatedThumbnailTests {
    private func gif(frames: Int, side: Int) throws -> Data {
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            output,
            UTType.gif.identifier as CFString,
            frames,
            nil
        ))
        CGImageDestinationSetProperties(
            destination,
            [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
        )
        for index in 0..<frames {
            let context = try #require(CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            for row in 0..<8 {
                context.setFillColor(CGColor(
                    red: Double(index) / Double(frames),
                    green: Double(row) / 8,
                    blue: 0.5,
                    alpha: 1
                ))
                context.fill(CGRect(x: 0, y: row * side / 8, width: side, height: side / 8))
            }
            try CGImageDestinationAddImage(
                destination, #require(context.makeImage()),
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.05]] as CFDictionary
            )
        }
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    @Test("a big copied GIF is shown from a smaller animated copy; the stored original is untouched")
    func whenBigGIF_thenCardGetsASmallerAnimatedCopy() async throws {
        let original = try gif(frames: 120, side: 900)
        let container = try ModelContainerSetup.makeInMemory()
        let service = StorageService(modelContainer: container)
        try await service.ingest(PasteboardCapture(
            typeIdentifier: "com.compuserve.gif", payload: original, payloadString: nil,
            contentHash: SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined()
        ))
        let item = try #require(try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first)

        let thumbnail = try #require(await ThumbnailService(modelContainer: container).thumbnail(
            for: item.id,
            maxPixel: 480
        ))

        #expect(thumbnail.isAnimated)
        #expect(thumbnail.data.count < original.count, "\(thumbnail.data.count) vs \(original.count)")
        let source = try #require(CGImageSourceCreateWithData(thumbnail.data as CFData, nil))
        #expect(CGImageSourceGetCount(source) <= 60 && CGImageSourceGetCount(source) > 1)
        let size = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect((size[kCGImagePropertyPixelWidth] as? Int ?? .max) <= 480, "the card copy is not scaled down")
        let stored = try #require(try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first?.blob?
            .decryptedData())
        #expect(stored == original, "pasting must still deliver the original GIF")
    }
}
