// SPDX-License-Identifier: MIT
import AppKit
import ImageIO
import PestoCore
import UniformTypeIdentifiers

/// One copy of each kind of clip, the way the pasteboard watcher would hand it to the store.
struct ClipKindFixture {
    let name: String
    let capture: PasteboardCapture
    /// What the clip is stored as, when that differs from what was copied (rich text is flattened at capture).
    let storedType: ClipboardType
}

enum ClipKindFixtures {
    static func capture(
        _ type: String, payload: Data, string: String? = nil, hash: String = UUID().uuidString
    )
    -> PasteboardCapture {
        PasteboardCapture(typeIdentifier: type, payload: payload, payloadString: string, contentHash: hash)
    }

    static func text(_ string: String) -> PasteboardCapture {
        capture("public.utf8-plain-text", payload: Data(string.utf8), string: string)
    }

    static func animatedGIF(frames: Int = 24, side: Int = 320) -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.gif.identifier as CFString, frames, nil
        ) else { preconditionFailure("no GIF destination") }
        CGImageDestinationSetProperties(
            destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
        )
        for index in 0..<frames {
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { preconditionFailure("no bitmap context") }
            let hue = CGFloat(index) / CGFloat(frames)
            context.setFillColor(NSColor(hue: hue, saturation: 0.8, brightness: 0.9, alpha: 1).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fillEllipse(in: CGRect(x: index * 6, y: side / 2 - 20, width: 40, height: 40))
            guard let image = context.makeImage() else { preconditionFailure("no frame") }
            CGImageDestinationAddImage(
                destination, image,
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.05]] as CFDictionary
            )
        }
        precondition(CGImageDestinationFinalize(destination))
        return output as Data
    }

    /// One of each kind. A different `variant` gives different content of the same size, so a test can copy a kind
    /// several times without the store treating the copies as duplicates.
    @MainActor
    static func all(variant: Int = 0) -> [ClipKindFixture] {
        let code = (0..<40).map { "func step\($0)(_ value: Int) -> Int { value &+ \($0 + variant) }" }
            .joined(separator: "\n")
        let sentence = "The quick brown fox jumps over the lazy dog. "
        let large = String(repeating: sentence, count: 120_000) + "variant \(variant)"
        let file = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app/Contents/Info.plist")
        let link = "https://developer.apple.com/documentation/swiftdata/\(variant)"
        return [
            ClipKindFixture(
                name: "text",
                capture: text("Meet at the north entrance at 14:30, bring the signed forms."),
                storedType: .text
            ),
            ClipKindFixture(name: "code", capture: text(code), storedType: .code),
            ClipKindFixture(
                name: "link",
                capture: capture("public.url", payload: Data(link.utf8), string: link),
                storedType: .url
            ),
            ClipKindFixture(
                name: "colour",
                capture: text(String(format: "#%06X", 0x1E90FF + variant * 257)),
                storedType: .color
            ),
            ClipKindFixture(
                name: "file", capture: capture(
                    "public.file-url",
                    payload: Data(file.absoluteString.utf8),
                    string: file.absoluteString
                ),
                storedType: .file
            ),
            ClipKindFixture(
                name: "picture 1920x1080", capture: capture(
                    "public.png",
                    payload: PictureFixtures.png(width: 1920 - variant, height: 1080, fill: .noise)
                ),
                storedType: .image
            ),
            ClipKindFixture(
                name: "screenshot 2880x1800", capture: capture(
                    "public.png",
                    payload: PictureFixtures.png(width: 2880 - variant, height: 1800)
                ),
                storedType: .image
            ),
            ClipKindFixture(
                name: "gif 24 frames",
                capture: capture("com.compuserve.gif", payload: animatedGIF(frames: 24 + variant)),
                storedType: .image
            ),
            ClipKindFixture(name: "large clip 5 MB", capture: text(large), storedType: .text)
        ]
    }
}
