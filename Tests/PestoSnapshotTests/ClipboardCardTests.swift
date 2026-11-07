// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SnapshotTesting
import SwiftData
import SwiftUI
import XCTest
@testable import Pesto

/// Snapshot tests for ClipboardCard — one per ClipboardType plus dark/light/RTL/focus variants.
///
/// Baselines live under __Snapshots__/ClipboardCardTests/ and are OS-specific.
/// Regenerate from the same macOS version that recorded them; CI excludes these tests
/// via the PestoCITests scheme until a matching runner is available.
@MainActor
final class ClipboardCardTests: XCTestCase {
    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainerSetup.makeInMemory()
        return ModelContext(container)
    }

    private func makeItem(
        in ctx: ModelContext,
        type: ClipboardType,
        preview: String = "Sample preview text",
        sensitivity: SensitivityCategory? = nil,
        maskedPreview: String? = nil,
        isPinned: Bool = false
    )
    -> ClipboardItem {
        let item = ClipboardItem(
            type: type,
            previewText: sensitivity != nil ? (maskedPreview ?? preview) : preview,
            sensitivity: sensitivity,
            sensitivityMaskedPreview: maskedPreview,
            contentHash: UUID().uuidString,
            byteSize: preview.utf8.count,
            deviceID: "test-device",
            sequenceNumber: 1,
            isPinned: isPinned
        )
        ctx.insert(item)
        return item
    }

    private func snapshotCard(
        _ card: some View,
        named name: String? = nil,
        colorScheme: ColorScheme = .dark,
        layoutDirection: LayoutDirection = .leftToRight,
        cardSize: CGSize = CGSize(width: 200, height: 180),
        solidShelfGround: String? = nil,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let ground = solidShelfGround.flatMap { Color(hex: $0) }
            ?? (colorScheme == .dark ? Color(white: 0.11) : Color(white: 0.9))
        let root = card
            .defaultAppStorage(AppDefaults.store)
            .environment(\.layoutDirection, layoutDirection)
            .environment(\.shelfDrawsGlass, solidShelfGround == nil ? nil : false)
            .preferredColorScheme(colorScheme)
            .frame(width: cardSize.width, height: cardSize.height)
            .padding(20)
            .background(ground)
        let controller = NSHostingController(rootView: root.inBrandAccent())
        // `preferredColorScheme` does not reach text drawn in a view that is not in a window: it takes the Mac's own
        // appearance (white text on the light card of the light picture).
        controller.view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        withSnapshotTesting(record: .missing) {
            assertSnapshot(
                of: controller,
                as: .image(size: CGSize(width: cardSize.width + 40, height: cardSize.height + 40)),
                named: name,
                file: file,
                testName: testName,
                line: line
            )
        }
    }

    // MARK: - Covered for sharing

    /// D-02: the cover for a screen share once sat on the card's own tint, so a picture's or a color's dominant color
    /// (orange, red) showed through "Hidden for sharing".
    func test_coveredColorCard_showsNoColor() throws {
        let ctx = try makeContext()
        let item = makeItem(in: ctx, type: .color, preview: "#2F7A49")
        let card = ClipboardCard(item: item, isPrivacyBlurred: true)
        let root = card
            .defaultAppStorage(AppDefaults.store)
            .preferredColorScheme(.dark)
            .frame(width: 200, height: 180)
        let controller = NSHostingController(rootView: root)
        controller.view.appearance = NSAppearance(named: .darkAqua)
        controller.view.frame = NSRect(x: 0, y: 0, width: 200, height: 180)
        let rep = try XCTUnwrap(controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds))
        controller.view.cacheDisplay(in: controller.view.bounds, to: rep)
        var mostSaturated = 0.0
        for (x, y) in [(20, 60), (100, 20), (180, 120), (60, 150)] {
            let color = try XCTUnwrap(rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
            mostSaturated = max(mostSaturated, color.saturationComponent)
        }
        XCTAssertLessThan(mostSaturated, 0.25, "the covered card still shows a color")
    }

    /// The cover is drawn over the card's own border, so it draws the focus ring itself.
    func test_coveredFocusedCard_drawsTheFocusRing() throws {
        let ctx = try makeContext()
        let item = makeItem(in: ctx, type: .text, preview: "plain")
        func edgeSaturation(focused: Bool) throws -> Double {
            let root = ClipboardCard(item: item, isFocused: focused, isPrivacyBlurred: true)
                .defaultAppStorage(AppDefaults.store)
                .environment(\.pestoAccent, .green)
                .preferredColorScheme(.dark)
                .frame(width: 200, height: 180)
            let controller = NSHostingController(rootView: root)
            controller.view.appearance = NSAppearance(named: .darkAqua)
            controller.view.frame = NSRect(x: 0, y: 0, width: 200, height: 180)
            let rep = try XCTUnwrap(controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds))
            controller.view.cacheDisplay(in: controller.view.bounds, to: rep)
            var most = 0.0
            for y in [60, 90, 120] {
                let color = try XCTUnwrap(rep.colorAt(x: 1, y: y)?.usingColorSpace(.sRGB))
                most = max(most, color.saturationComponent)
            }
            return most
        }
        XCTAssertLessThan(try edgeSaturation(focused: false), 0.25)
        XCTAssertGreaterThan(try edgeSaturation(focused: true), 0.4, "the covered, focused card shows no ring")
    }

    func test_coveredCard_showsNumberKindAndAge() throws {
        let ctx = try makeContext()
        let item = makeItem(in: ctx, type: .url, preview: "https://example.com")
        snapshotCard(ClipboardCard(item: item, shortcutNumber: 2, isPrivacyBlurred: true))
    }

    // MARK: - Text

    func test_textCard() throws {
        let ctx = try makeContext()
        let item = makeItem(in: ctx, type: .text, preview: "Quick brown fox\njumped over the lazy dog today")
        snapshotCard(ClipboardCard(item: item))
    }

    func test_textCard_lightMode() throws {
        let ctx = try makeContext()
        let item = makeItem(in: ctx, type: .text, preview: "Light mode text card variant")
        snapshotCard(ClipboardCard(item: item), named: "light", colorScheme: .light)
    }

    /// ADR 0035: on the solid shelf a light card is opaque white on the theme's own ground (the Basil light ground).
    func test_textCard_onTheSolidShelf_light() throws {
        let ctx = try makeContext()
        let item = makeItem(in: ctx, type: .text, preview: "Light card on the solid shelf")
        snapshotCard(
            ClipboardCard(item: item), named: "solidLight", colorScheme: .light, solidShelfGround: BrandPalette.garlic
        )
    }

    /// Reduce Transparency turns the shelf solid; the card must be the same white on it, not the system's window grey.
    func test_textCard_onTheSolidShelf_underReduceTransparency_light() throws {
        let ctx = try makeContext()
        let item = makeItem(in: ctx, type: .text, preview: "Light card, Reduce Transparency, Parmesan")
        snapshotCard(
            ClipboardCard(item: item).environment(\.reduceTransparencyOverride, true),
            named: "solidReducedLight", colorScheme: .light,
            solidShelfGround: AppTheme.parmesan.groundHex(dark: false)
        )
    }

    func test_textCard_onTheSolidShelf_dark() throws {
        let ctx = try makeContext()
        let item = makeItem(in: ctx, type: .text, preview: "Dark card on the solid shelf")
        snapshotCard(
            ClipboardCard(item: item), named: "solidDark", colorScheme: .dark,
            solidShelfGround: BrandPalette.darkSurface
        )
    }

    func test_textCard_rtl() throws {
        let ctx = try makeContext()
        let item = makeItem(in: ctx, type: .text, preview: "שלום עולם\nזהו טקסט בעברית\nלבדיקת כיוון RTL")
        snapshotCard(ClipboardCard(item: item), named: "rtl", layoutDirection: .rightToLeft)
    }

    // MARK: - Card sizes and themes (docs/design/card-typography.md, option B)

    private static let longText = (1...12).map { "Line \($0) of a long note that keeps going" }.joined(separator: "\n")

    private func withCardWidth(_ width: Int, _ body: () throws -> Void) rethrows {
        let previous = AppDefaults.store.value(for: Setting.cardWidth)
        AppDefaults.store.set(width, for: Setting.cardWidth)
        defer { AppDefaults.store.set(previous, for: Setting.cardWidth) }
        try body()
    }

    func test_textCard_paragraphs() throws {
        let ctx = try makeContext()
        let item = makeItem(
            in: ctx, type: .text,
            preview: "\n\n  Release notes\u{2028}for version 2\n\n\n\nFixed the shelf.\n\nAdded the footer count.\n"
        )
        item.textLength = item.previewText.count
        snapshotCard(ClipboardCard(item: item))
    }

    func test_textCard_small() throws {
        try withCardWidth(160) {
            let ctx = try makeContext()
            let item = makeItem(in: ctx, type: .text, preview: Self.longText)
            snapshotCard(ClipboardCard(item: item), cardSize: CardMetrics.dimensions(width: 160))
        }
    }

    func test_textCard_large() throws {
        try withCardWidth(240) {
            let ctx = try makeContext()
            let item = makeItem(in: ctx, type: .text, preview: Self.longText)
            snapshotCard(ClipboardCard(item: item), cardSize: CardMetrics.dimensions(width: 240))
        }
    }

    func test_textCard_perTheme() throws {
        let ctx = try makeContext()
        for theme in AppTheme.allCases {
            let item = makeItem(in: ctx, type: .text, preview: "Quick brown fox\njumped over the lazy dog today")
            item.sourceAppName = "Safari"
            item.sourceDominantColorHex = "#1E88E5"
            let accent = Color.pestoAccent(stored: "", theme: theme.rawValue)
            snapshotCard(
                ClipboardCard(item: item).environment(\.pestoAccent, accent),
                named: theme.rawValue
            )
        }
    }

    // MARK: - Code

    func test_codeCard() throws {
        let ctx = try makeContext()
        let item = makeItem(in: ctx, type: .code, preview: "func greet() -> String {\n    return \"hello\"\n}")
        snapshotCard(ClipboardCard(item: item))
    }

    // MARK: - URL

    func test_urlCard() throws {
        let ctx = try makeContext()
        let item = makeItem(in: ctx, type: .url, preview: "https://github.com/pointfreeco/swift-snapshot-testing")
        snapshotCard(ClipboardCard(item: item))
    }

    // MARK: - File

    func test_fileCard() throws {
        let ctx = try makeContext()
        let item = makeItem(in: ctx, type: .file, preview: "file:///Users/user/Documents/report.pdf")
        snapshotCard(ClipboardCard(item: item))
    }

    // MARK: - Color

    func test_colorCard() throws {
        let ctx = try makeContext()
        let item = makeItem(in: ctx, type: .color, preview: "#2F7A49")
        snapshotCard(ClipboardCard(item: item))
    }

    // MARK: - Glyph

    func test_singleEmojiCard() throws {
        let ctx = try makeContext()
        let item = makeItem(in: ctx, type: .text, preview: "🍝")
        snapshotCard(ClipboardCard(item: item))
        snapshotCard(ClipboardCard(item: item), named: "light", colorScheme: .light)
    }

    func test_singleSymbolCard() throws {
        let ctx = try makeContext()
        let item = makeItem(in: ctx, type: .text, preview: "→")
        snapshotCard(ClipboardCard(item: item))
        snapshotCard(ClipboardCard(item: item), named: "light", colorScheme: .light)
    }

    // MARK: - Image

    func test_imagePlaceholderCard() throws {
        let ctx = try makeContext()
        let item = makeItem(in: ctx, type: .image, preview: "")
        snapshotCard(ClipboardCard(item: item))
    }

    // MARK: - Sensitive content

    func test_sensitiveCard_creditCard() throws {
        let ctx = try makeContext()
        let item = makeItem(
            in: ctx,
            type: .text,
            preview: "4111111111111111",
            sensitivity: .creditCard,
            maskedPreview: "•••• •••• •••• 1111"
        )
        snapshotCard(ClipboardCard(item: item))
    }

    func test_sensitiveCard_apiKey() throws {
        let ctx = try makeContext()
        let item = makeItem(
            in: ctx,
            type: .text,
            preview: "sk-proj-abc123xyz",
            sensitivity: .apiKey,
            maskedPreview: "sk-proj-••••••••••••••"
        )
        snapshotCard(ClipboardCard(item: item))
    }

    // MARK: - Pinned

    func test_pinnedCard() throws {
        let ctx = try makeContext()
        let item = makeItem(in: ctx, type: .text, preview: "Pinned item always visible", isPinned: true)
        snapshotCard(ClipboardCard(item: item))
    }

    // MARK: - Focused (keyboard selection ring)

    func test_focusedCard() throws {
        let ctx = try makeContext()
        let item = makeItem(in: ctx, type: .text, preview: "Keyboard-focused card")
        snapshotCard(ClipboardCard(item: item, isFocused: true))
    }

    // MARK: - Reduce Transparency (AdaptiveMaterial / GlassPanelBackground fallback)

    /// Guards the opaque fallback added for macOS 27's transparency-intensity slider (and the
    /// existing "Reduce Transparency" accessibility setting): custom translucent fills must
    /// swap to an opaque surface, not just inherit whatever the system materials do on their own.
    func test_textCard_reducedTransparency() throws {
        let ctx = try makeContext()
        let item = makeItem(in: ctx, type: .text, preview: "Reduced-transparency text card")
        snapshotCard(
            ClipboardCard(item: item)
                .environment(\.reduceTransparencyOverride, true)
        )
    }

    func test_privacyBlurredCard_reducedTransparency() throws {
        let ctx = try makeContext()
        let item = makeItem(in: ctx, type: .text, sensitivity: .apiKey, maskedPreview: "sk-••••••••")
        snapshotCard(
            ClipboardCard(item: item, isPrivacyBlurred: true)
                .environment(\.reduceTransparencyOverride, true)
        )
    }

    // MARK: - Content first (ADR 0026)

    private func samplePicture(aspect: CGFloat) -> NSImage {
        let size = CGSize(width: 480, height: 480 / aspect)
        return NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [.systemTeal, .systemYellow, .white])?.draw(in: rect, angle: 35)
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: rect.width * 0.3, dy: rect.height * 0.3)).fill()
            return true
        }
    }

    private func pictureItem(
        in ctx: ModelContext, aspect: CGFloat, animated: Bool = false, source: String = "Preview"
    )
    -> ClipboardItem {
        let item = makeItem(in: ctx, type: .image, preview: "")
        item.sourceAppName = source
        item.byteSize = 98_304
        ThumbnailCache.shared.store(
            .init(image: samplePicture(aspect: aspect), isAnimated: animated, byteSize: item.byteSize), for: item.id
        )
        return item
    }

    func test_pictureCard_fillsTheCard() throws {
        defer { ThumbnailCache.shared.clear() }
        let ctx = try makeContext()
        let item = pictureItem(in: ctx, aspect: 1.0)
        snapshotCard(ClipboardCard(item: item, shortcutNumber: 1))
        snapshotCard(ClipboardCard(item: item, shortcutNumber: 1), named: "light", colorScheme: .light)
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

    func test_gifCard_fillsTheCardWithABadge() throws {
        defer { ThumbnailCache.shared.clear() }
        let ctx = try makeContext()
        let item = pictureItem(in: ctx, aspect: 1.2, animated: true, source: "Safari")
        snapshotCard(ClipboardCard(item: item, shortcutNumber: 2))
    }

    func test_pictureCard_small() throws {
        defer { ThumbnailCache.shared.clear() }
        try withCardWidth(160) {
            let ctx = try makeContext()
            let item = pictureItem(in: ctx, aspect: 1.0)
            snapshotCard(ClipboardCard(item: item, shortcutNumber: 1), cardSize: CardMetrics.dimensions(width: 160))
        }
    }

    func test_colorCard_lightFillTakesBlackInk() throws {
        let ctx = try makeContext()
        let item = makeItem(in: ctx, type: .color, preview: "#C9A227")
        item.sourceAppName = "Digital Color Meter"
        snapshotCard(ClipboardCard(item: item, shortcutNumber: 3))
        snapshotCard(ClipboardCard(item: item, shortcutNumber: 3), named: "light", colorScheme: .light)
    }

    func test_largeTextCard_twoSteps() throws {
        let ctx = try makeContext()
        for (name, text) in [
            ("up24", "Meeting at 3pm"),
            ("up48", "The quarterly numbers look good, send them on")
        ] {
            let item = makeItem(in: ctx, type: .text, preview: text)
            item.sourceAppName = "Notes"
            snapshotCard(ClipboardCard(item: item, shortcutNumber: 1), named: name)
        }
    }

    func test_largeTextCard_small() throws {
        try withCardWidth(160) {
            let ctx = try makeContext()
            let item = makeItem(in: ctx, type: .text, preview: "The quarterly numbers look good, send them on")
            snapshotCard(ClipboardCard(item: item), cardSize: CardMetrics.dimensions(width: 160))
        }
    }

    func test_linkCard_leadsWithTheRealHost() throws {
        let ctx = try makeContext()
        let item = makeItem(
            in: ctx, type: .url,
            preview: "https://news.example.com:8443/2026/11/story-about-a-very-long-headline?token=s3cr3t#frag"
        )
        snapshotCard(ClipboardCard(item: item, shortcutNumber: 1))
    }

    func test_linkCard_longHostTakesTheSmallerStep() throws {
        let ctx = try makeContext()
        let item = makeItem(
            in: ctx, type: .url, preview: "https://documentation.internal.example.com/guides/start"
        )
        snapshotCard(ClipboardCard(item: item, shortcutNumber: 1))
    }

    func test_linkCard_hostStaysOnOneLineAtTheNarrowestAndWidestCard() throws {
        for (name, host) in [("sixteen", "news.example.com"), ("twentyFour", "documentation.example.io")] {
            for width in [160, 240] {
                try withCardWidth(width) {
                    let ctx = try makeContext()
                    let item = makeItem(in: ctx, type: .url, preview: "https://\(host)/guides/start")
                    snapshotCard(
                        ClipboardCard(item: item, shortcutNumber: 1),
                        named: "\(name)\(width)",
                        cardSize: CardMetrics.dimensions(width: width)
                    )
                }
            }
        }
    }

    func test_linkCard_withMetadataKeepsItsRichBody() throws {
        let ctx = try makeContext()
        let item = makeItem(in: ctx, type: .url, preview: "https://news.example.com/2026/11/story")
        item.ogTitle = "A story worth reading"
        item.ogSiteName = "Example News"
        snapshotCard(ClipboardCard(item: item, shortcutNumber: 1))
    }

    func test_pictureCard_pasteCountPillOverABrightPicture() throws {
        defer { ThumbnailCache.shared.clear() }
        let ctx = try makeContext()
        let item = pictureItem(in: ctx, aspect: 1.0)
        item.pasteCount = 4
        snapshotCard(ClipboardCard(item: item, shortcutNumber: 1))
    }

    func test_shortCoveredText_showsTheCoverFace() throws {
        let ctx = try makeContext()
        let item = makeItem(in: ctx, type: .text, preview: "hunter2")
        snapshotCard(ClipboardCard(item: item, isPrivacyBlurred: true))
    }
}
