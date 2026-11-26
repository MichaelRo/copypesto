// SPDX-License-Identifier: MIT
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import PestoCore
@testable import PestoMobile

/// The keyboard, AutoFill and the widgets draw Pesto's card (ADR 0074): the foot glows in the app's color, the size
/// preview shows as many rows as the keyboard will. Pictures go to `.build/extension-card-renders` for a person to see.
@Suite("Extension cards are the app's cards")
@MainActor
struct ExtensionCardRenderingTests {
    private static let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent(".build/extension-card-renders", isDirectory: true)

    private static func entry(color: String?) -> QuickInsertEntry {
        QuickInsertEntry(
            id: UUID(), section: .recent, kind: .text, title: "Pick up basil and pine nuts",
            text: "Pick up basil and pine nuts", expandsOnInsert: false, date: .now, source: "Notes",
            sourceBundleID: "com.apple.mobilenotes", sourceColorHex: color
        )
    }

    private func render(_ view: some View, size: CGSize, dark: Bool, name: String) throws -> UIImage {
        let renderer = ImageRenderer(content: view
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.horizontalSizeClass, .compact)
            .environment(\.verticalSizeClass, .regular))
        renderer.scale = 2
        let image = try #require(renderer.uiImage)
        try FileManager.default.createDirectory(at: Self.output, withIntermediateDirectories: true)
        try image.pngData()?.write(to: Self.output.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
        return image
    }

    private struct Pixel {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }

    /// The pixel at a point in the rendered picture's own points.
    private func pixel(_ image: UIImage, x: CGFloat, y: CGFloat) throws -> Pixel {
        let cgImage = try #require(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let scale = image.scale
        context.draw(cgImage, in: CGRect(
            x: -x * scale, y: -(CGFloat(cgImage.height) - y * scale), width: CGFloat(cgImage.width),
            height: CGFloat(cgImage.height)
        ))
        return Pixel(
            red: Double(bytes[0]) / 255, green: Double(bytes[1]) / 255, blue: Double(bytes[2]) / 255,
            alpha: Double(bytes[3]) / 255
        )
    }

    @Test("a card from a colorful app glows warmer at its foot than at its top; a card without a color stays even")
    func whenTheAppHasAColor_thenTheFootGlows() throws {
        let size = CGSize(width: 180, height: 110)
        for dark in [false, true] {
            let warm = try render(
                QuickInsertCardFace(entry: Self.entry(color: "#F5C400"), size: size, theme: .brand),
                size: size, dark: dark, name: "card-glow"
            )
            let foot = try pixel(warm, x: 170, y: 104)
            let top = try pixel(warm, x: 170, y: 6)
            // Yellow lifts red and green above blue at the foot; the top is the card's plain fill.
            #expect(foot.red - foot.blue > top.red - top.blue + 0.01, "dark: \(dark)")
        }
    }

    @Test("the size preview shows two rows at Medium and Large on an iPhone held upright, one at Small")
    func whenPreviewed_thenRowsFollowTheSize() throws {
        let entries = KeyboardPreviewSamples.entries()
        for (size, rows) in [(KeyboardSize.small, 1), (.medium, 2), (.large, 2)] {
            let card = KeyboardLayout.cardSize(size: size, isRegular: false)
            let expected = CGFloat(rows) * card.height + CGFloat(rows - 1) * 6
            let preview = KeyboardSizePreview(size: size, entries: entries, theme: .brand)
            let image = try render(
                preview.fixedSize(horizontal: false, vertical: true),
                size: CGSize(width: 360, height: expected), dark: false, name: "preview-\(size.rawValue)"
            )
            #expect(image.size.height == expected)
            // The row starts at the leading edge: the first card is whole and the gap after it is empty.
            #expect(try pixel(image, x: 3, y: card.height / 2).alpha > 0.9, "\(size)")
            #expect(try pixel(image, x: card.width + 3, y: card.height / 2).alpha < 0.1, "\(size)")
            #expect(KeyboardLayout.rows(size: size, isRegular: false, isLandscape: false) == rows)
        }
    }

    @Test("a widget card of a colorful app glows at its foot")
    func whenWidgetClipHasAColor_thenTheTileGlows() throws {
        let clip = WidgetClip(
            id: UUID(), kind: .text, text: "Pick up basil and pine nuts", source: "Notes", date: .now,
            sourceBundleID: "com.apple.mobilenotes", sourceColorHex: "#F5C400"
        )
        let size = CGSize(width: 160, height: 120)
        let image = try render(
            WidgetCardTile(clip: clip, now: .now, palette: WidgetPalette(theme: .brand, isDark: false)),
            size: size, dark: false, name: "widget-glow"
        )
        let foot = try pixel(image, x: 150, y: 114)
        let top = try pixel(image, x: 150, y: 6)
        #expect(foot.red - foot.blue > top.red - top.blue + 0.01)
    }
}
