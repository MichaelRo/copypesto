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
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let root = card
            .defaultAppStorage(AppDefaults.store)
            .environment(\.layoutDirection, layoutDirection)
            .preferredColorScheme(colorScheme)
            .frame(width: cardSize.width, height: cardSize.height)
            .padding(20)
            .background(colorScheme == .dark ? Color(white: 0.11) : Color(white: 0.9))
        let controller = NSHostingController(rootView: root)
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
}
