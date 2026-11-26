// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PictureFixtures {
    enum Fill {
        case flat
        case noise
        /// Dark bands on a light ground where `pattern`'s low eight bits are set: pictures of one size that are
        /// neither lookalikes nor pixel-identical, as two screenshots of different windows are.
        case bands(pattern: Int)
    }

    /// A PNG of the given size. `.flat` compresses to a few megabytes at any size; `.noise` does not compress, so its
    /// file size follows its pixel count.
    static func png(width: Int, height: Int, fill: Fill = .flat) -> Data {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else
        {
            preconditionFailure("no bitmap context for \(width)x\(height)")
        }
        switch fill {
        case .flat:
            context.setFillColor(CGColor(red: 0.5, green: 0.6, blue: 0.5, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        case let .bands(pattern):
            context.setFillColor(CGColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1))
            let band = width / 8
            for index in 0..<8 where (pattern >> index) & 1 == 1 {
                context.fill(CGRect(x: index * band, y: 0, width: band, height: height))
            }
        case .noise:
            var state: UInt64 = 0x9E37_79B9_7F4A_7C15
            for index in 0..<(width * height) {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let value = UInt32(truncatingIfNeeded: state >> 33)
                pixels[index * 4] = UInt8(truncatingIfNeeded: value)
                pixels[index * 4 + 1] = UInt8(truncatingIfNeeded: value >> 8)
                pixels[index * 4 + 2] = UInt8(truncatingIfNeeded: value >> 16)
                pixels[index * 4 + 3] = 255
            }
        }
        let output = NSMutableData()
        let type = UTType.png.identifier as CFString
        guard let image = context.makeImage() else { preconditionFailure("no image for \(width)x\(height)") }
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else {
            preconditionFailure("cannot encode \(width)x\(height)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
