// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SnapshotTesting
import SwiftData
import SwiftUI
import XCTest
@testable import Pesto

@MainActor
extension ClipboardCardTests {
    func samplePicture(aspect: CGFloat) -> NSImage {
        samplePicture(size: CGSize(width: 480, height: 480 / aspect))
    }

    func samplePicture(size: CGSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [.systemTeal, .systemYellow, .white])?.draw(in: rect, angle: 35)
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: rect.width * 0.3, dy: rect.height * 0.3)).fill()
            return true
        }
    }

    func pictureItem(
        in ctx: ModelContext, aspect: CGFloat, animated: Bool = false, source: String = "Preview",
        bundleID: String? = nil, pixels: CGSize? = nil
    )
    -> ClipboardItem {
        let item = makeItem(in: ctx, type: .image, preview: "")
        item.sourceAppName = source
        item.sourceBundleID = bundleID
        item.byteSize = 98_304
        if let pixels {
            item.pixelWidth = Int(pixels.width)
            item.pixelHeight = Int(pixels.height)
        }
        let image = pixels.map { samplePicture(size: $0) } ?? samplePicture(aspect: aspect)
        ThumbnailCache.shared.store(.init(image: image, isAnimated: animated, byteSize: item.byteSize), for: item.id)
        return item
    }

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

    // MARK: - ADR 0080

    func test_pictureCard_phoneScreenshotKeepsNearlyTheWholeHeight() throws {
        defer { ThumbnailCache.shared.clear() }
        let ctx = try makeContext()
        let item = pictureItem(
            in: ctx, aspect: 0.4615, source: "Screenshot", bundleID: "com.apple.screencaptureui",
            pixels: CGSize(width: 1179, height: 2556)
        )
        snapshotCard(ClipboardCard(item: item, shortcutNumber: 3))
    }

    func test_pictureCard_squareScreenCaptureIsShownWhole() throws {
        defer { ThumbnailCache.shared.clear() }
        let ctx = try makeContext()
        let item = pictureItem(
            in: ctx, aspect: 1.0, source: "Screenshot", bundleID: "com.apple.screencaptureui",
            pixels: CGSize(width: 1200, height: 1200)
        )
        snapshotCard(ClipboardCard(item: item, shortcutNumber: 4))
    }

    func test_pictureCard_receiptFillsFromItsTop() throws {
        defer { ThumbnailCache.shared.clear() }
        let ctx = try makeContext()
        let item = pictureItem(in: ctx, aspect: 0.3, source: "Preview", pixels: CGSize(width: 600, height: 2000))
        snapshotCard(ClipboardCard(item: item, shortcutNumber: 5))
    }

    func test_pictureCard_smallIconIsDrawnAtTwiceItsSizeWithHardEdges() throws {
        defer { ThumbnailCache.shared.clear() }
        let ctx = try makeContext()
        let item = pictureItem(in: ctx, aspect: 1.0, source: "Preview", pixels: CGSize(width: 32, height: 32))
        snapshotCard(ClipboardCard(item: item, shortcutNumber: 6))
    }

    func test_pictureCard_panoramaIsCenteredAboveTheFacts() throws {
        defer { ThumbnailCache.shared.clear() }
        let ctx = try makeContext()
        let item = pictureItem(in: ctx, aspect: 4, source: "Photos", pixels: CGSize(width: 4000, height: 1000))
        snapshotCard(ClipboardCard(item: item, shortcutNumber: 7))
    }

    func test_pictureCard_whenFocused_thenTheLineSaysItsDimensions() throws {
        defer { ThumbnailCache.shared.clear() }
        let ctx = try makeContext()
        let item = pictureItem(
            in: ctx,
            aspect: 16.0 / 9.0,
            source: "Preview",
            pixels: CGSize(width: 1920, height: 1080)
        )
        snapshotCard(ClipboardCard(item: item, isFocused: true))
    }

    func test_gifCard_wideIsShownWholeOverAStillBlurredCopy() throws {
        defer { ThumbnailCache.shared.clear() }
        let ctx = try makeContext()
        let item = pictureItem(in: ctx, aspect: 1.5, animated: true, source: "Safari")
        snapshotCard(ClipboardCard(item: item, shortcutNumber: 2))
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
            headerSample.brightnessComponent, 0.5,
            "light-mode picture header scrim should harmonize with the light card surface instead of a black fade"
        )
    }
}
