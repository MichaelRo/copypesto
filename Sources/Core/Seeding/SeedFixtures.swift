// SPDX-License-Identifier: MIT
import AppKit
import CoreGraphics
import CryptoKit
import ImageIO

/// Deterministic clipboard history for `-UITestMode`. Captures go through the real ingest pipeline, so
/// classification, masking, encryption and rendering match what live captures produce.
public enum SeedFixtures {
    private struct RGB {
        let red: Double
        let green: Double
        let blue: Double
    }

    private struct Sample {
        let text: String
        let app: String
    }

    /// Oldest first: the last sample ends up newest in the grid.
    private static let basicSamples: [Sample] = [
        Sample(text: "Remember to renew the domain before October 3rd.", app: "com.apple.Notes"),
        Sample(
            text: "Pesto keeps your clipboard history on this Mac. Press the shortcut anywhere to bring back "
                + "anything you copied earlier, then paste it straight into the app you were using.",
            app: "com.apple.Safari"
        ),
        Sample(
            text: "func greet(_ name: String) -> String {\n    let message = \"Hello, \\(name)!\"\n"
                + "    return message\n}",
            app: "com.apple.dt.Xcode"
        ),
        Sample(
            text: "{\n  \"name\": \"pesto\",\n  \"version\": \"1.0.0\",\n  \"private\": true\n}",
            app: "com.apple.dt.Xcode"
        ),
        Sample(
            text: "https://developer.apple.com/design/human-interface-guidelines/materials",
            app: "com.apple.Safari"
        ),
        Sample(text: "https://github.com/example/pesto/issues/42", app: "com.apple.Safari"),
        Sample(text: "#2F7A49", app: "com.apple.ColorSyncUtility"),
        Sample(text: "4242 4242 4242 4242", app: "com.apple.Safari"),
        Sample(text: "sk-ant-api03-EXAMPLEEXAMPLEEXAMPLEEXAMPLE1234567890abcdef", app: "com.apple.Terminal"),
        Sample(text: "hello@example.com", app: "com.apple.mail"),
        Sample(text: "Team lunch is at 12:30 on Thursday, booked under Alex.", app: "com.apple.iChat"),
        Sample(text: "Quarterly report draft — final review pending.", app: "com.apple.TextEdit")
    ]

    /// Captures oldest first, one minute apart, the last one at `now`, so relative timestamps ("3m ago")
    /// are stable and the grid order is deterministic.
    public static func captures(for profile: SeedProfile, now: Date = .now) -> [PasteboardCapture] {
        let captures = switch profile {
        case .empty: [PasteboardCapture]()
        case .basic: basicCaptures()
        case .large: largeCaptures()
        case .files: fileCaptures()
        case .showcase: showcaseCaptures()
        case .marketing: MarketingSeed.captures()
        case .mixed: MixedSeed.captures()
        case .animated: animatedCaptures()
        case .remote: remoteCaptures()
        case .latency: LatencySeed.captures()
        case .pictures: MixedSeed.pictureCaptures()
        }
        return captures.enumerated().map { index, capture in
            capture.with(timestamp: now.addingTimeInterval(-Double(captures.count - 1 - index) * 60))
        }
    }

    public static func hash(of payload: Data) -> String {
        payload.sha256Hex
    }

    private static func remoteCaptures() -> [PasteboardCapture] {
        let fromPhone = Data("Copied on the phone".utf8)
        return [
            textCapture("Copied on this Mac", app: "com.apple.Notes"),
            PasteboardCapture(
                typeIdentifier: NSPasteboard.PasteboardType.string.rawValue, payload: fromPhone,
                payloadString: "Copied on the phone", contentHash: hash(of: fromPhone), isRemote: true
            ),
            textCapture("Also copied on this Mac", app: "com.apple.Safari")
        ]
    }

    private static func basicCaptures() -> [PasteboardCapture] {
        var captures = basicSamples.map { textCapture($0.text, app: $0.app) }
        // Two images, inserted after the first few items so they sit mid-history.
        captures.insert(
            imageCapture(color: RGB(red: 0.20, green: 0.45, blue: 0.90), stripe: RGB(red: 1, green: 1, blue: 1)),
            at: 5
        )
        captures.insert(
            imageCapture(
                color: RGB(red: 0.18, green: 0.48, blue: 0.29),
                stripe: RGB(red: 0.96, green: 0.94, blue: 0.85)
            ),
            at: 9
        )
        return captures
    }

    private static func largeCaptures() -> [PasteboardCapture] {
        let topics = ["invoice", "meeting", "recipe", "release notes", "address", "todo", "snippet", "quote"]
        return (0..<5000).map { index in
            let topic = topics[index % topics.count]
            let text = index % 10 == 0
                ? "let value\(index) = compute(\(index))"
                : "Clip #\(String(format: "%04d", index)) — \(topic) sample text for scroll performance"
            return textCapture(text, app: "com.apple.TextEdit")
        }
    }

    /// Oldest first, so the last entry is the newest card on the shelf. All invented: a small pesto-world (recipes,
    /// shopping, a little code, colours, pictures drawn in code) so screenshots show what someone might really copy,
    /// without anything personal or any real brand, page or artwork. Plain English on purpose.
    private enum ShowcaseClip {
        case text(String, app: String)
        case picture(Data)
    }

    private static func showcaseClips() -> [ShowcaseClip] {
        [
            .text(
                "Pesto keeps your clipboard history on this Mac, encrypted. Press the shortcut anywhere to bring "
                    + "back anything you copied earlier.",
                app: "com.apple.Safari"
            ),
            .text("4242 4242 4242 4242", app: "com.apple.Safari"),
            .text("1Z999AA10123456784", app: "com.apple.Safari"),
            .text("Rosa's Deli, 123 Basil Lane. Call (555) 010-0142.", app: "com.apple.Notes"),
            .text("orders@copypesto.net", app: "com.apple.mail"),
            .text(
                "def scale_pesto(servings: int) -> dict:\n"
                    + "    assert servings > 0, \"Nonna is watching\"\n"
                    + "    return {k: v * servings / 4 for k, v in recipe.items()}",
                app: "com.apple.dt.Xcode"
            ),
            .text(
                ":root {\n  --basil: #2F7A49;\n  --pine-nut: #EBD9B4;\n  --parmesan: #F6EFD9;\n  --mortar: #1F2320;\n}",
                app: "com.apple.dt.Xcode"
            ),
            .text(
                "git commit -m \"fix(sauce): remove heavy cream (closes #1: Italian blasphemy)\"",
                app: "com.apple.Terminal"
            ),
            .text(
                "1. Toast the pine nuts.\n2. Crush the basil, sea salt and garlic in a mortar.\n"
                    + "3. Drizzle Taggiasca olive oil.\n4. Fold in Parmigiano Reggiano last.",
                app: "com.apple.Notes"
            ),
            .text(
                "Shopping list: Genovese basil, pine nuts, garlic, Taggiasca oil, Parmigiano Reggiano, lemons.",
                app: "com.apple.Notes"
            ),
            .text(
                "2 packed cups of Genovese basil is about 60 g. Pine nuts 50 g. Olive oil 100 ml.",
                app: "com.apple.Notes"
            ),
            .text("https://copypesto.net/docs/shortcuts/", app: "com.apple.Safari"),
            .text("Pesto night at Dana's, Friday at 7:00 pm. Bring the basil and pecorino.", app: "com.apple.iCal"),
            .text(
                "{\n  \"recipe\": \"pesto genovese\",\n  \"basil\": \"60 g\",\n  \"pine_nuts\": \"50 g\",\n"
                    + "  \"servings\": 4\n}",
                app: "com.apple.dt.Xcode"
            ),
            .picture(ShowcaseArt.ingredientPalette()),
            .text("#F6EFD9", app: "com.apple.ColorSyncUtility"),
            .picture(ShowcaseArt.pineNuts()),
            .text("#2F7A49", app: "com.apple.ColorSyncUtility"),
            .text("https://example.com/recipes/pesto-genovese", app: "com.apple.Safari"),
            .text("Toast the pine nuts 3 min, not 4.", app: "com.apple.Notes"),
            .picture(ShowcaseArt.basilLeaves())
        ]
    }

    private static func showcaseCaptures() -> [PasteboardCapture] {
        showcaseClips().map { clip in
            switch clip {
            case let .text(text, app): textCapture(text, app: app)
            case let .picture(data): pictureCapture(data)
            }
        }
    }

    private static func animatedCaptures() -> [PasteboardCapture] {
        let gif = animatedGIFData()
        return [
            textCapture("Pesto keeps your clipboard history on this Mac.", app: "com.apple.Notes"),
            PasteboardCapture(
                typeIdentifier: "com.compuserve.gif",
                payload: gif,
                frontmostBundleID: "com.apple.Safari",
                contentHash: hash(of: gif)
            ),
            textCapture("Toast the pine nuts 3 min, not 4.", app: "com.apple.Notes"),
            animatedFileCapture(gif)
        ]
    }

    /// A GIF *file* (Finder, Downloads), which becomes a file clip rather than a picture clip.
    private static func animatedFileCapture(_ gif: Data) -> PasteboardCapture {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("pesto-seed-dance.gif")
        try? gif.write(to: file)
        return fileCapture([file.path])
    }

    /// Four frames of plain colour, a tenth of a second each, so any two frames drawn a moment apart differ.
    static func animatedGIFData(side: Int = 240) -> Data {
        let colours = [
            RGB(red: 0.9, green: 0.2, blue: 0.2), RGB(red: 0.2, green: 0.7, blue: 0.3),
            RGB(red: 0.2, green: 0.4, blue: 0.9), RGB(red: 0.95, green: 0.8, blue: 0.2)
        ]
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, "com.compuserve.gif" as CFString, colours.count, nil
        ) else { return Data() }
        CGImageDestinationSetProperties(
            destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
        )
        for colour in colours {
            guard let context = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return Data() }
            context.setFillColor(red: colour.red, green: colour.green, blue: colour.blue, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            guard let frame = context.makeImage() else { return Data() }
            CGImageDestinationAddImage(
                destination, frame, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary
            )
        }
        return CGImageDestinationFinalize(destination) ? output as Data : Data()
    }

    static func pictureCapture(_ payload: Data) -> PasteboardCapture {
        PasteboardCapture(
            typeIdentifier: NSPasteboard.PasteboardType.png.rawValue,
            payload: payload,
            frontmostBundleID: "com.apple.Preview",
            contentHash: hash(of: payload)
        )
    }

    private static func fileCaptures() -> [PasteboardCapture] {
        [
            fileCapture(["/etc/hosts"]),
            fileCapture(["/Users/pesto/Documents/basil-harvest-notes.pdf"]),
            fileCapture(["/etc/hosts", "/Users/pesto/Documents/pine-nut-inventory.csv"])
        ]
    }

    private static func fileCapture(_ paths: [String]) -> PasteboardCapture {
        let text = FileClip.encode(paths.map { URL(fileURLWithPath: $0) })
        let payload = Data(text.utf8)
        return PasteboardCapture(
            typeIdentifier: NSPasteboard.PasteboardType.fileURL.rawValue,
            payload: payload,
            payloadString: text,
            frontmostBundleID: "com.apple.finder",
            contentHash: hash(of: payload)
        )
    }

    static func textCapture(_ text: String, app: String) -> PasteboardCapture {
        let payload = Data(text.utf8)
        return PasteboardCapture(
            typeIdentifier: NSPasteboard.PasteboardType.string.rawValue,
            payload: payload,
            payloadString: text,
            frontmostBundleID: app,
            contentHash: hash(of: payload)
        )
    }

    private static func imageCapture(color: RGB, stripe: RGB) -> PasteboardCapture {
        let payload = pngData(color: color, stripe: stripe)
        return PasteboardCapture(
            typeIdentifier: NSPasteboard.PasteboardType.png.rawValue,
            payload: payload,
            frontmostBundleID: "com.apple.Preview",
            contentHash: hash(of: payload)
        )
    }

    private static func pngData(color: RGB, stripe: RGB) -> Data {
        let width = 240
        let height = 160
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return Data() }
        context.setFillColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: stripe.red, green: stripe.green, blue: stripe.blue, alpha: 1)
        context.fill(CGRect(x: 0, y: height / 3, width: width, height: height / 6))
        guard let image = context.makeImage() else { return Data() }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) ?? Data()
    }
}
