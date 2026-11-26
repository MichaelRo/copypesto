// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PestoCore

@Suite("Picture fingerprint")
struct PictureFingerprintTests {
    /// A picture wider than `PictureFingerprint.maxSide`, so it is compared scaled down. `mark` adds a small dark
    /// block.
    private func picture(
        mark: Bool = false, space name: CFString = CGColorSpace.sRGB, type: UTType = .png,
        properties: [CFString: Any] = [:]
    ) throws
    -> Data {
        let width = 1600
        let height = 900
        let space = try #require(CGColorSpace(name: name))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for line in 0..<20 {
            context.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.2, alpha: 1))
            context.fill(CGRect(x: 100, y: 40 + line * 40, width: 300 + line * 31, height: 14))
        }
        if mark {
            context.fill(CGRect(x: 1400, y: 450, width: 40, height: 14))
        }
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
        return output as Data
    }

    @Test("a small change in a file read the same way rules the other picture out, whichever is asked")
    func whenOneWordDiffers_thenRuledOut() throws {
        let plain = try #require(PictureFingerprint(imageData: picture()))
        let marked = try #require(PictureFingerprint(imageData: picture(mark: true)))

        #expect(plain.rulesOut(marked))
        #expect(marked.rulesOut(plain))
    }

    @Test("the same pixels with other metadata are not ruled out")
    func whenOnlyMetadataDiffers_thenSameFingerprint() throws {
        let first = try picture(properties: [kCGImagePropertyDPIWidth: 72, kCGImagePropertyDPIHeight: 72])
        let second = try picture(properties: [kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144])
        #expect(first != second)

        #expect(PictureFingerprint(imageData: first) == PictureFingerprint(imageData: second))
    }

    @Test("files that are read differently say nothing about each other")
    func whenReadingDiffers_thenNotRuledOut() throws {
        let png = try #require(PictureFingerprint(imageData: picture()))
        let others = try [
            picture(mark: true, properties: [kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGInterlaceType: 1]]),
            picture(mark: true, space: CGColorSpace.displayP3),
            picture(mark: true, properties: [kCGImagePropertyOrientation: 3])
        ]

        for other in others {
            let fingerprint = try #require(PictureFingerprint(imageData: other))
            #expect(!png.rulesOut(fingerprint))
            #expect(!fingerprint.rulesOut(png))
        }
    }

    @Test("a TIFF has no fingerprint: tiled and planar files scale the same pixels differently, unannounced")
    func whenTIFF_thenNone() throws {
        #expect(try PictureFingerprint(imageData: picture(type: .tiff)) == nil)
    }

    @Test("a lossy picture has no fingerprint, because a close copy of it counts as the same one")
    func whenLossy_thenNone() throws {
        #expect(try PictureFingerprint(imageData: picture(type: .jpeg)) == nil)
        #expect(try PictureFingerprint(imageData: picture(type: .heic)) == nil)
    }

    @Test("reading both at once gives what each pass gives on its own")
    func whenReadSideBySide_thenSameResults() throws {
        let pictures = try [
            picture(),
            picture(properties: [kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGInterlaceType: 1]]),
            picture(type: .tiff),
            picture(type: .jpeg),
            Data("hello".utf8)
        ]

        for data in pictures {
            let both = PictureFingerprint.withCoarseHash(imageData: data)

            #expect(both.hash == PerceptualHasher.hash(imageData: data))
            #expect(both.fingerprint == PictureFingerprint(imageData: data))
        }
    }

    @Test("more pictures read at once than the Mac has cores all finish")
    func whenManyAtOnce_thenAllFinish() async throws {
        let data = try picture()
        let callers = ProcessInfo.processInfo.activeProcessorCount * 3

        let hashes = await withTaskGroup(of: String?.self) { group in
            for _ in 0..<callers {
                group.addTask { PictureFingerprint.withCoarseHash(imageData: data).hash }
            }
            return await group.reduce(into: [String?]()) { $0.append($1) }
        }

        #expect(hashes.count == callers)
        #expect(hashes.allSatisfy { $0 == PerceptualHasher.hash(imageData: data) })
    }

    @Test("data that is not a picture has no fingerprint")
    func whenNotAPicture_thenNone() {
        #expect(PictureFingerprint(imageData: Data("hello".utf8)) == nil)
    }

    @Test("a picture is sealed with its clip's other metadata and is not empty metadata")
    func whenOnlyAFingerprint_thenMetadataIsKept() throws {
        let fingerprint = try #require(PictureFingerprint(imageData: picture()))
        let metadata = ItemMetadata(pictureFingerprint: fingerprint)

        #expect(!metadata.isEmpty)
        let decoded = try JSONDecoder().decode(ItemMetadata.self, from: JSONEncoder().encode(metadata))
        #expect(decoded == metadata)
    }
}
