// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import Testing
@testable import Pesto

/// `.clipped()` on the paragraph layout made the text of a card render white in a light appearance, and no test looked
/// at
/// the colour: the pixels are read here.
@Suite("CardParagraphText colour")
@MainActor
struct CardParagraphTextTests {
    /// The darkest and the lightest luminance (0...1) of what the view draws on a white ground in `appearance`.
    private func extremes(in appearance: NSAppearance.Name) throws -> (darkest: Double, lightest: Double) {
        let view = CardParagraphText(
            paragraphs: ["Quick brown fox", "jumped over the lazy dog"], fontSize: 13, design: .default, budget: 90
        )
        .frame(width: 200, height: 100, alignment: .topLeading)
        .background(Color.white)
        let controller = NSHostingController(rootView: view)
        controller.view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        controller.view.appearance = NSAppearance(named: appearance)
        controller.view.layoutSubtreeIfNeeded()
        let bitmap = try #require(controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds))
        controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
        var darkest = 1.0, lightest = 0.0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let luminance = 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color
                    .blueComponent
                darkest = min(darkest, luminance)
                lightest = max(lightest, luminance)
            }
        }
        return (darkest, lightest)
    }

    @Test("in a light appearance the text is dark on the light ground, never white")
    func whenLight_thenTextIsDark() throws {
        let light = try extremes(in: .aqua)
        #expect(light.darkest < 0.4, "no dark text pixel: the text was drawn white (darkest \(light.darkest))")
    }
}
