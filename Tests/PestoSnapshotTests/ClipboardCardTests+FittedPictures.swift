// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SnapshotTesting
import SwiftUI
import XCTest
@testable import Pesto

@MainActor
extension ClipboardCardTests {
    func test_gifCard_whenNarrowAndFocused_thenTheAgeOutlastsTheGIFLabel() throws {
        defer { ThumbnailCache.shared.clear() }
        try withCardWidth(160) {
            let ctx = try makeContext()
            let item = pictureItem(in: ctx, aspect: 1.0, animated: true, source: "Safari")
            snapshotCard(
                ClipboardCard(item: item, isFocused: true, shortcutNumber: 3),
                cardSize: CardMetrics.dimensions(width: 160)
            )
        }
    }

    func test_pictureCard_wideIsShownWholeOverABlurredCopy() throws {
        defer { ThumbnailCache.shared.clear() }
        let ctx = try makeContext()
        let item = pictureItem(in: ctx, aspect: 1.5, source: "Preview")
        snapshotCard(ClipboardCard(item: item, shortcutNumber: 1))
        snapshotCard(ClipboardCard(item: item, shortcutNumber: 1), named: "light", colorScheme: .light)
    }

    func test_pictureCard_tallScreenshotIsFitted() throws {
        defer { ThumbnailCache.shared.clear() }
        let ctx = try makeContext()
        let item = pictureItem(in: ctx, aspect: 0.4, source: "Screenshot")
        snapshotCard(ClipboardCard(item: item, shortcutNumber: 3))
    }

    func test_whenPictureCardInLightMode_thenHeaderScrimHarmonizesWithLightThemeSurface() throws {
        defer { ThumbnailCache.shared.clear() }
        let ctx = try makeContext()
        let item = pictureItem(in: ctx, aspect: 1.5, source: "Preview")
        let root = ClipboardCard(item: item, shortcutNumber: 1)
            .defaultAppStorage(AppDefaults.store)
            .preferredColorScheme(.light)
            .frame(width: 200, height: 180)
            .inBrandAccent()
        let controller = NSHostingController(rootView: root)
        controller.view.appearance = NSAppearance(named: .aqua)
        controller.view.frame = NSRect(x: 0, y: 0, width: 200, height: 180)
        let rep = try XCTUnwrap(controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds))
        controller.view.cacheDisplay(in: controller.view.bounds, to: rep)
        // Top header band (y = 14 from top -> bitmap y = 14) must be bright (harmonized with light theme surface),
        // never a harsh dark black fade (< 0.5 brightness).
        let headerSample = try XCTUnwrap(rep.colorAt(x: 160, y: 14)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(
            headerSample.brightnessComponent, 0.75,
            "light-mode picture header scrim should harmonize with the light card surface instead of a black fade"
        )
    }
}
