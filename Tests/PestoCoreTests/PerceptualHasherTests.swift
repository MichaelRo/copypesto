// SPDX-License-Identifier: MIT
import AppKit
import CoreGraphics
import Testing
@testable import PestoCore

@Suite("PerceptualHasher")
struct PerceptualHasherTests {
    @Test("hamming distance of identical hashes is 0")
    func whenIdentical_thenZero() {
        let a = "deadbeefcafebabe"
        let b = "deadbeefcafebabe"
        #expect(PerceptualHasher.hammingDistance(a, b) == 0)
    }

    @Test("hamming distance of single-bit difference is 1")
    func whenOneBitDiff_thenOne() {
        // 0xDE...BABE vs 0xDE...BABF (last byte differs by 1 bit)
        let a = "deadbeefcafebabe"
        let b = "deadbeefcafebabf"
        #expect(PerceptualHasher.hammingDistance(a, b) == 1)
    }

    @Test("hamming distance is symmetric")
    func hammingIsSymmetric() {
        let a = "1234567890abcdef"
        let b = "fedcba0987654321"
        let ab = PerceptualHasher.hammingDistance(a, b)
        let ba = PerceptualHasher.hammingDistance(b, a)
        #expect(ab != nil)
        #expect(ab == ba)
    }

    @Test("invalid hex returns nil")
    func whenInvalidHex_thenNil() {
        #expect(PerceptualHasher.hammingDistance("not-hex", "deadbeefcafebabe") == nil)
    }

    @Test("threshold is reasonable (≤8)")
    func thresholdIsReasonable() {
        // Anything ≥ 9 would be too permissive for a 64-bit hash.
        #expect(PerceptualHasher.similarityThreshold <= 8)
        #expect(PerceptualHasher.similarityThreshold >= 1)
    }

    @Test("hashes a solid red 8x8 image")
    func whenSolidImage_thenHashable() {
        let cs = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = 8 * 4
        var pixels = [UInt8](repeating: 0, count: 8 * 8 * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = 255 // R
            pixels[i + 1] = 0 // G
            pixels[i + 2] = 0 // B
            pixels[i + 3] = 255 // A
        }
        let image = pixels.withUnsafeMutableBufferPointer { buf -> CGImage? in
            CGContext(
                data: buf.baseAddress,
                width: 8,
                height: 8,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: cs,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.makeImage()
        }
        #expect(image != nil)
        let hash = image.flatMap { PerceptualHasher.hash(cgImage: $0) }
        #expect(hash != nil)
        #expect(hash?.count == 16) // 16 hex chars = 64 bits
    }

    private func picture(editedBlock: Bool) throws -> NSBitmapImageRep {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        for x in 0..<256 {
            for y in 0..<256 {
                let shade = CGFloat((x + y) % 256) / 255
                let edited = editedBlock && (100..<108).contains(x) && (100..<108).contains(y)
                let color = edited
                    ? NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1)
                    : NSColor(calibratedRed: shade, green: 1 - shade, blue: 0.5, alpha: 1)
                rep.setColor(color, atX: x, y: y)
            }
        }
        return rep
    }

    @Test("a small edit leaves the coarse hash within the threshold but changes the pixel digest")
    func whenSmallEdit_thenPixelDigestDiffers() throws {
        let original = try #require(picture(editedBlock: false).representation(using: .png, properties: [:]))
        let edited = try #require(picture(editedBlock: true).representation(using: .png, properties: [:]))

        let originalHash = try #require(PerceptualHasher.hash(imageData: original))
        let editedHash = try #require(PerceptualHasher.hash(imageData: edited))
        let distance = try #require(PerceptualHasher.hammingDistance(originalHash, editedHash))
        #expect(distance <= PerceptualHasher.similarityThreshold)
        #expect(PerceptualHasher.pixelDigest(imageData: original) != PerceptualHasher.pixelDigest(imageData: edited))
    }

    @Test("the same pixels in another lossless encoding have the same digest")
    func whenReencodedLosslessly_thenDigestMatches() throws {
        let rep = try picture(editedBlock: false)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        let tiff = try #require(rep.tiffRepresentation)

        let digest = try #require(PerceptualHasher.pixelDigest(imageData: png))
        #expect(digest == PerceptualHasher.pixelDigest(imageData: tiff))
    }

    @Test("data that is not an image has no digest")
    func whenNotAnImage_thenNoDigest() {
        #expect(PerceptualHasher.pixelDigest(imageData: Data("nope".utf8)) == nil)
    }

    @Test("only the newest few lookalikes are nominated for the expensive pixel comparison")
    func whenManyLookalikes_thenTheNewestFewAreNominated() {
        let near = "deadbeefcafebabe"
        let existing: [(id: Int, hash: String?)] = (1...12).map { ($0, near) }

        let nominated = PerceptualHasher.nominees(for: near, among: existing, limit: 5)

        #expect(nominated == [1, 2, 3, 4, 5], "the list is newest first, so the first five are the newest")
    }

    @Test("a clip with no hash, or a hash beyond the threshold, is never nominated")
    func whenDissimilarOrUnhashed_thenNotNominated() {
        let candidate = "deadbeefcafebabe"
        let existing: [(id: Int, hash: String?)] = [
            (1, nil), (2, "0000000000000000"), (3, "deadbeefcafebabf"), (4, "not hex")
        ]

        #expect(PerceptualHasher.nominees(for: candidate, among: existing, limit: 5) == [3])
    }
}
