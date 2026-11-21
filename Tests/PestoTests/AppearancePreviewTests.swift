// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI
import Testing
@testable import Pesto

@Suite("Appearance and Shelf position previews")
@MainActor
struct AppearancePreviewTests {
    private func renderBitmap(of view: some View, size: CGSize) throws -> NSBitmapImageRep {
        let hosting = SafeHostingView(pesto: view.frame(width: size.width, height: size.height))
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep
    }

    @Test("compact ThemeShelfMiniature fits three cards cleanly inside a 74x46 tile")
    func whenCompactMetricsUsedAt74x46_thenCardsAndLinesFitWithoutOverflow() {
        let innerSize = CGSize(width: 64, height: 36) // 74x46 minus 5pt padding on each side
        let metrics = ThemeShelfMiniature.metrics(compact: true)
        let cardWidth = (innerSize.width - metrics.horizontalPadding * 2 - metrics.cardSpacing * 2) / 3
        let cardHeight = innerSize.height - metrics.topPadding - metrics.bottomPadding

        #expect(cardWidth >= 15)
        #expect(cardHeight >= 24)
        #expect(metrics.topInset * 2 + metrics.primaryLineWidth <= cardWidth)
        #expect(metrics.bottomInset * 2 + metrics.dotSize + metrics.footSpacing + metrics.footLineWidth <= cardWidth)
        let topBlockHeight = metrics.topInset + metrics.lineHeight * 2 + metrics.lineSpacing
        let bottomBlockHeight = metrics.bottomInset + metrics.dotSize
        #expect(topBlockHeight + bottomBlockHeight < cardHeight - 4)
    }

    @Test("AppearanceModePreview at 74x46 renders three clean cards with clear gaps and no capsule overflow")
    func whenAppearanceModePreviewRenderedAtSettingsSize_thenCardsDoNotOverflowIntoGaps() throws {
        let size = CGSize(width: 74, height: 46)
        let rep = try renderBitmap(
            of: AppearanceModePreview(mode: .light, themeRaw: AppTheme.basil.rawValue),
            size: size
        )
        let scale = CGFloat(rep.pixelsWide) / size.width

        for gapPointX in [27.5, 46.5] {
            let pixelX = Int((gapPointX * scale).rounded())
            for pointY in stride(from: 11.0, through: 35.0, by: 1.0) {
                let pixelY = Int((pointY * scale).rounded())
                let color = try #require(rep.colorAt(x: pixelX, y: pixelY)?.usingColorSpace(.sRGB))
                let luminance = 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color
                    .blueComponent
                #expect(
                    luminance > 0.85,
                    "Expected clean light ground in card gap at (\(gapPointX), \(pointY)), got luminance \(luminance)"
                )
            }
        }

        let card0Pixel = try #require(
            rep.colorAt(x: Int((13.0 * scale).rounded()), y: Int((23.0 * scale).rounded()))?.usingColorSpace(.sRGB)
        )
        let card0Luminance = 0.2126 * card0Pixel.redComponent + 0.7152 * card0Pixel.greenComponent + 0.0722 * card0Pixel
            .blueComponent
        #expect(
            card0Luminance < 0.93,
            "Expected card 0 fill at (13, 23) with compact horizontal padding, got luminance \(card0Luminance)"
        )
    }

    @Test("ShelfPositionPreview aligns card dots at bottomLeading rather than topLeading")
    func whenShelfPositionPreviewRendered_thenDotIsAtBottomLeading() throws {
        let size = CGSize(width: 78, height: 48)
        let rep = try renderBitmap(
            of: ShelfPositionPreview(position: .bottom, themeRaw: AppTheme.basil.rawValue)
                .environment(\.pestoAccent, Color(red: 1, green: 0, blue: 0)),
            size: size
        )
        let scale = CGFloat(rep.pixelsWide) / size.width

        func countRedDotPixels(yPointRange: ClosedRange<Double>) -> Int {
            var count = 0
            let minX = Int((15.0 * scale).rounded())
            let maxX = Int((26.0 * scale).rounded())
            let minY = Int((yPointRange.lowerBound * scale).rounded())
            let maxY = Int((yPointRange.upperBound * scale).rounded())
            for x in minX...maxX {
                for y in minY...maxY {
                    if let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                       color.redComponent - color.greenComponent > 0.25,
                       color.redComponent - color.blueComponent > 0.25
                    {
                        count += 1
                    }
                }
            }
            return count
        }

        let topHalfRedPixels = countRedDotPixels(yPointRange: 11.0...17.5)
        let bottomHalfRedPixels = countRedDotPixels(yPointRange: 20.5...27.0)
        #expect(topHalfRedPixels == 0, "Expected no dot in top half of card 0, found \(topHalfRedPixels)")
        #expect(
            bottomHalfRedPixels >= 3,
            "Expected bottomLeading dot in bottom half of card 0, found \(bottomHalfRedPixels)"
        )
    }

    @Test("AppearanceModePreview dark and system modes at 74x46 keep clear dark gaps and light/dark split")
    func whenDarkAndSystemAppearancePreviewsRendered_thenGapsRemainCleanAndSplitDistinct() throws {
        let size = CGSize(width: 74, height: 46)
        let darkRep = try renderBitmap(
            of: AppearanceModePreview(mode: .dark, themeRaw: AppTheme.basil.rawValue),
            size: size
        )
        let darkScale = CGFloat(darkRep.pixelsWide) / size.width
        for gapPointX in [27.5, 46.5] {
            let pixelX = Int((gapPointX * darkScale).rounded())
            for pointY in stride(from: 11.0, through: 35.0, by: 2.0) {
                let pixelY = Int((pointY * darkScale).rounded())
                let color = try #require(darkRep.colorAt(x: pixelX, y: pixelY)?.usingColorSpace(.sRGB))
                let luminance = 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color
                    .blueComponent
                #expect(
                    luminance < 0.25,
                    "Expected clean dark ground in card gap at (\(gapPointX), \(pointY)), got luminance \(luminance)"
                )
            }
        }

        let systemRep = try renderBitmap(
            of: AppearanceModePreview(mode: .system, themeRaw: AppTheme.basil.rawValue),
            size: size
        )
        let sysScale = CGFloat(systemRep.pixelsWide) / size.width
        let leftColor = try #require(
            systemRep.colorAt(x: Int((10.0 * sysScale).rounded()), y: Int((23.0 * sysScale).rounded()))?
                .usingColorSpace(.sRGB)
        )
        let rightColor = try #require(
            systemRep.colorAt(x: Int((64.0 * sysScale).rounded()), y: Int((23.0 * sysScale).rounded()))?
                .usingColorSpace(.sRGB)
        )
        let leftLuminance = 0.2126 * leftColor.redComponent + 0.7152 * leftColor.greenComponent + 0.0722 * leftColor
            .blueComponent
        let rightLuminance = 0.2126 * rightColor.redComponent + 0.7152 * rightColor.greenComponent + 0.0722 * rightColor
            .blueComponent
        #expect(leftLuminance > 0.70)
        #expect(rightLuminance < 0.30)
    }
}
