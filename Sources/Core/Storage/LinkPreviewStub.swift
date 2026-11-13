// SPDX-License-Identifier: MIT
import AppKit
import CoreGraphics
import ImageIO

/// What a benchmark's link preview answers with instead of a page: a title and a picture drawn in code, after a fixed
/// wait, so the shelf does the same work each run and no request leaves the Mac.
enum LinkPreviewStub {
    static func load(_ url: URL, delayMillis: Int) async throws -> URLPreviewResult {
        try await Task.sleep(for: .milliseconds(delayMillis))
        let seed = abs(url.absoluteString.hashValue % 10_000)
        let isGIFLink = url.path.lowercased().contains("gif")
        return URLPreviewResult(
            title: "Stub page \(seed)",
            ogImageData: isGIFLink ? animation() : picture(hue: Double(seed % 360) / 360), faviconData: nil,
            siteName: "example.com"
        )
    }

    /// What a link straight to a GIF answers with: four colored frames, so a test can tell a card that plays from one
    /// that shows a still.
    private static func animation() -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, "com.compuserve.gif" as CFString, 4, nil
        ) else { return nil }
        CGImageDestinationSetProperties(
            destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
        )
        for hue in [0.0, 0.25, 0.5, 0.75] {
            guard let frame = frame(hue: hue) else { return nil }
            CGImageDestinationAddImage(
                destination, frame, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary
            )
        }
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    private static func frame(hue: Double) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: 240, height: 130, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(NSColor(hue: hue, saturation: 0.6, brightness: 0.9, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 240, height: 130))
        return context.makeImage()
    }

    private static func picture(hue: Double) -> Data? {
        let (width, height) = (480, 260)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(NSColor(hue: hue, saturation: 0.4, brightness: 0.9, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(NSColor(hue: hue, saturation: 0.7, brightness: 0.5, alpha: 1).cgColor)
        context.fill(CGRect(x: 40, y: 60, width: 300, height: 90))
        return context.makeImage()
            .flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
    }
}
