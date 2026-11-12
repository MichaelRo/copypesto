// SPDX-License-Identifier: MIT
import AppKit
import CoreGraphics

/// What a benchmark's link preview answers with instead of a page: a title and a picture drawn in code, after a fixed
/// wait, so the shelf does the same work each run and no request leaves the Mac.
enum LinkPreviewStub {
    static func load(_ url: URL, delayMillis: Int) async throws -> URLPreviewResult {
        try await Task.sleep(for: .milliseconds(delayMillis))
        let seed = abs(url.absoluteString.hashValue % 10_000)
        return URLPreviewResult(
            title: "Stub page \(seed)", ogImageData: picture(hue: Double(seed % 360) / 360), faviconData: nil,
            siteName: "example.com"
        )
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
