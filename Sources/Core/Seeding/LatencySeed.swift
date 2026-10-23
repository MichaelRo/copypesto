// SPDX-License-Identifier: MIT
import AppKit

/// One clip of each kind for the paste and copy latency bench. Oldest first, so the shelf shows them newest first as
/// text, code, link, colour, file, picture, GIF, large clip: the bench pastes card N with ⌘N. Only seeded in UI-test
/// mode.
enum LatencySeed {
    static let largeClipRepeats = 120_000

    static func captures() -> [PasteboardCapture] {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("pesto-latency-seed.txt")
        try? Data("A file the bench pastes.\n".utf8).write(to: file)
        let fileText = FileClip.encode([file])
        let picture = MixedSeed.pngData(seed: 7)
        let gif = SeedFixtures.animatedGIFData(side: 320)
        let newestFirst: [PasteboardCapture] = [
            SeedFixtures.textCapture(
                "Meet at the north entrance at 14:30, bring the signed forms.",
                app: "com.apple.Notes"
            ),
            SeedFixtures.textCapture(
                (0..<40).map { "func step\($0)(_ value: Int) -> Int { value &+ \($0) }" }.joined(separator: "\n"),
                app: "com.apple.dt.Xcode"
            ),
            PasteboardCapture(
                typeIdentifier: "public.url",
                payload: Data("https://example.com/documentation/swiftdata".utf8),
                payloadString: "https://example.com/documentation/swiftdata",
                frontmostBundleID: "com.apple.Safari",
                contentHash: SeedFixtures.hash(of: Data("latency-link".utf8))
            ),
            SeedFixtures.textCapture("#1E90FF", app: "com.apple.ColorSyncUtility"),
            PasteboardCapture(
                typeIdentifier: NSPasteboard.PasteboardType.fileURL.rawValue,
                payload: Data(fileText.utf8),
                payloadString: fileText,
                frontmostBundleID: "com.apple.finder",
                contentHash: SeedFixtures.hash(of: Data(fileText.utf8))
            ),
            PasteboardCapture(
                typeIdentifier: NSPasteboard.PasteboardType.png.rawValue,
                payload: picture,
                frontmostBundleID: "com.apple.screencaptureui",
                contentHash: SeedFixtures.hash(of: picture)
            ),
            PasteboardCapture(
                typeIdentifier: "com.compuserve.gif",
                payload: gif,
                frontmostBundleID: "com.apple.Safari",
                contentHash: SeedFixtures.hash(of: gif)
            ),
            SeedFixtures.textCapture(
                String(repeating: "The quick brown fox jumps over the lazy dog. ", count: largeClipRepeats),
                app: "com.apple.TextEdit"
            )
        ]
        return newestFirst.reversed()
    }
}
