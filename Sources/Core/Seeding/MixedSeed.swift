// SPDX-License-Identifier: MIT
import AppKit
import CoreGraphics

/// A history that looks like someone's real one, for measuring the shelf: mostly text of every length, some links, code
/// and colours, and one clip in twelve a large picture of the kind a screenshot makes. Deterministic, so two runs
/// measure
/// the same shelf. Only ever seeded in UI-test mode.
enum MixedSeed {
    static let count = 1200

    static func captures(count: Int = MixedSeed.count) -> [PasteboardCapture] {
        (0..<count).map { capture(at: $0) }
    }

    /// Nothing but pictures, every one 1600 x 1000 and different, so scrolling to the end makes the shelf draw and
    /// release hundreds of 480-pixel thumbnails (P-06).
    static func pictureCaptures(count: Int = 300) -> [PasteboardCapture] {
        (0..<count).map { image(at: $0) }
    }

    private static func capture(at index: Int) -> PasteboardCapture {
        switch index % 12 {
        case 0: image(at: index)
        case 3: SeedFixtures.textCapture("https://example.com/articles/\(index)/read-more", app: "com.apple.Safari")
        case 5: SeedFixtures.textCapture(code(at: index), app: "com.apple.dt.Xcode")
        case 8: SeedFixtures.textCapture(color(at: index), app: "com.apple.ColorSyncUtility")
        default: SeedFixtures.textCapture(text(at: index), app: sources[index % sources.count])
        }
    }

    private static let sources = ["com.apple.TextEdit", "com.apple.Notes", "com.apple.mail", "com.apple.MobileSMS"]
    private static let words = [
        "basil", "pine", "nuts", "garlic", "olive", "oil", "parmesan", "toast", "blend", "season", "invoice", "meeting",
        "friday", "draft", "review", "release", "notes", "address", "street", "quote", "reminder", "follow", "up"
    ]

    private static func text(at index: Int) -> String {
        let length = 4 + (index * 7) % 60
        let body = (0..<length).map { words[($0 * 5 + index) % words.count] }.joined(separator: " ")
        return "Clip \(index): \(body)."
    }

    private static func code(at index: Int) -> String {
        "func total\(index)(_ values: [Int]) -> Int {\n    values.reduce(0, +) * \(index % 9 + 1)\n}"
    }

    private static func color(at index: Int) -> String {
        String(format: "#%06X", (index * 2_654_435) & 0xFFFFFF)
    }

    private static func image(at index: Int) -> PasteboardCapture {
        let payload = pngData(seed: index)
        return PasteboardCapture(
            typeIdentifier: NSPasteboard.PasteboardType.png.rawValue,
            payload: payload,
            frontmostBundleID: "com.apple.screencaptureui",
            contentHash: SeedFixtures.hash(of: payload)
        )
    }

    /// 1600 x 1000 with a gradient and a few dozen rectangles placed from the index, so no two are alike and the file
    /// is
    /// not trivially small, as with a real screenshot.
    static func pngData(seed: Int) -> Data {
        let width = 1600
        let height = 1000
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return Data() }
        var state = UInt64(truncatingIfNeeded: seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407)
        func next() -> CGFloat {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat((state >> 33) & 0xFFFF) / 65_535
        }
        let hue = next()
        context.setFillColor(NSColor(hue: hue, saturation: 0.35, brightness: 0.95, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for _ in 0..<400 {
            context
                .setFillColor(NSColor(hue: next(), saturation: 0.6, brightness: 0.4 + next() * 0.6, alpha: 1).cgColor)
            context.fill(CGRect(x: next() * 1500, y: next() * 900, width: 10 + next() * 120, height: 6 + next() * 50))
        }
        addPhotoNoise(to: context, width: width, height: height, state: &state)
        guard let image = context.makeImage() else { return Data() }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) ?? Data()
    }

    /// A band of noise standing in for a photograph, which is what makes a real screenshot's file large.
    private static func addPhotoNoise(to context: CGContext, width: Int, height: Int, state: inout UInt64) {
        guard let base = context.data else { return }
        let bytesPerRow = context.bytesPerRow
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        for row in (height / 5)..<(height * 4 / 5) {
            for column in (width / 4)..<(width * 3 / 4) {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let offset = row * bytesPerRow + column * 4
                pixels[offset] = UInt8(truncatingIfNeeded: state >> 40)
                pixels[offset + 1] = UInt8(truncatingIfNeeded: state >> 48)
                pixels[offset + 2] = UInt8(truncatingIfNeeded: state >> 56)
                pixels[offset + 3] = 255
            }
        }
    }
}
