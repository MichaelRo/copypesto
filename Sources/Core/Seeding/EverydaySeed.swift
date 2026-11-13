// SPDX-License-Identifier: MIT
import AppKit
import CoreGraphics

/// What a real clipboard holds, for judging how the shelf looks and not how it scrolls: white and dark screenshots,
/// long
/// links, chat, code, an address, one secret. Deterministic, a dozen clips, only ever seeded in UI-test mode. Not
/// `MixedSeed`, which the benches measure over weeks and must not change.
enum EverydaySeed {
    static func captures() -> [PasteboardCapture] {
        let chat = "com.tinyspeck.slackmacgap"
        let browser = "com.google.Chrome"
        return [
            SeedFixtures.textCapture("Sounds good, thanks!", app: "com.apple.MobileSMS"),
            SeedFixtures.textCapture("#1D4ED8", app: "com.apple.ColorSyncUtility"),
            SeedFixtures.textCapture(
                "SELECT u.id, u.email, COUNT(o.id) AS orders\nFROM users u\nLEFT JOIN orders o ON o.user_id = u.id\n"
                    + "WHERE u.created_at > '2026-01-01'\nGROUP BY u.id\nHAVING COUNT(o.id) > 3\nORDER BY orders DESC;",
                app: "com.apple.Terminal"
            ),
            screenshot(dark: true),
            SeedFixtures.textCapture("1Z999AA10123456784", app: "com.apple.mail"),
            SeedFixtures.textCapture(
                "Hi Dana,\n\nFollowing up on the invoice from October. Could you confirm the PO number and whether "
                    + "the net-30 terms still apply? I have attached the revised statement with the two corrections "
                    + "we discussed on the call.\n\nBest,\nSam",
                app: "com.apple.mail"
            ),
            SeedFixtures.textCapture("ok", app: chat),
            SeedFixtures.textCapture(
                "https://docs.google.com/spreadsheets/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit?gid=0#gid=0",
                app: browser
            ),
            SeedFixtures.textCapture(
                "sk-ant-api03-EXAMPLEEXAMPLEEXAMPLEEXAMPLE1234567890abcdef",
                app: "com.apple.Terminal"
            ),
            SeedFixtures.textCapture(
                "guard let index = items.firstIndex(of: target) else {\n    throw LookupError.missing(target)\n}\n"
                    + "var updated = items[index]\nupdated.isDone = true",
                app: "com.apple.dt.Xcode"
            ),
            SeedFixtures.textCapture(
                "can you look at the staging deploy when you get a sec? the health check has been flapping since "
                    + "about 2 and I can't tell if it's the new config or the LB",
                app: chat
            ),
            SeedFixtures.textCapture(
                "https://github.com/apple/swift-evolution/blob/main/proposals/0430-transferring-parameters.md",
                app: browser
            ),
            SeedFixtures.textCapture("14 Rue de la Paix, 75002 Paris", app: "com.apple.Notes"),
            screenshot(dark: false)
        ]
    }

    private static func screenshot(dark: Bool) -> PasteboardCapture {
        let payload = png(dark: dark)
        return PasteboardCapture(
            typeIdentifier: NSPasteboard.PasteboardType.png.rawValue,
            payload: payload,
            frontmostBundleID: "com.apple.screencaptureui",
            contentHash: SeedFixtures.hash(of: payload)
        )
    }

    private static func png(dark: Bool) -> Data {
        let width = 1600
        let height = 1000
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return Data() }
        let ground: CGFloat = dark ? 0.09 : 1.0
        let ink: CGFloat = dark ? 0.75 : 0.25
        context.setFillColor(CGColor(gray: ground, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: dark ? 0.16 : 0.94, alpha: 1))
        context.fill(CGRect(x: 0, y: height - 90, width: width, height: 90))
        if !dark {
            context.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.9, alpha: 1))
            context.fill(CGRect(x: 1320, y: height - 68, width: 220, height: 46))
        }
        for row in 0..<16 {
            let rowWidth = 500 + (row * 397) % 800
            context.setFillColor(CGColor(gray: ink, alpha: row % 5 == 0 ? 0.9 : 0.45))
            context.fill(CGRect(x: 90, y: height - 170 - row * 50, width: rowWidth, height: row % 5 == 0 ? 22 : 14))
        }
        guard let image = context.makeImage() else { return Data() }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) ?? Data()
    }
}
