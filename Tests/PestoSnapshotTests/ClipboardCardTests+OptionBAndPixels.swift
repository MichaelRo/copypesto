// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SnapshotTesting
import SwiftData
import SwiftUI
import XCTest
@testable import Pesto

extension ClipboardCardTests {
    // MARK: - Option B matrix (sizes × themes × source apps)

    func test_optionBTypography_acrossSizesThemesAndSourceApps() throws {
        let ctx = try makeContext()
        let sizes = [160, 200, 240]
        let sourceApps = [
            ("Safari", "#1E88E5"),
            ("Notes", "#F5C518"),
            ("Terminal", "#2E2E2E")
        ]
        for width in sizes {
            withCardWidth(width) {
                for theme in AppTheme.allCases {
                    let accent = Color.pestoAccent(stored: AccentChoice.defaultStored, theme: theme.rawValue)
                    for (appName, hex) in sourceApps {
                        let item = makeItem(in: ctx, type: .text, preview: Self.longText)
                        item.sourceAppName = appName
                        item.sourceDominantColorHex = hex
                        snapshotCard(
                            ClipboardCard(item: item, shortcutNumber: 1)
                                .environment(\.pestoAccent, accent),
                            named: "\(width)-\(theme.rawValue)-\(appName.lowercased())",
                            cardSize: CardMetrics.dimensions(width: width),
                            solidShelfGround: theme.groundHex(dark: true)
                        )
                    }
                }
            }
        }
    }

    // MARK: - AppIconChoice dock icon assets

    func test_appIconChoice_dockIconAssets() {
        let size = CGSize(width: 120, height: 120)
        for choice in AppIconChoice.allCases {
            XCTAssertNotNil(
                NSImage(named: choice.previewImageName),
                "Missing asset for \(choice.rawValue): \(choice.previewImageName)"
            )
            let root = Image(choice.previewImageName)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .padding(12)
                .background(Color(white: 0.14))
                .preferredColorScheme(.dark)
            let controller = NSHostingController(rootView: root)
            controller.view.appearance = NSAppearance(named: .darkAqua)
            withSnapshotTesting(record: .missing) {
                assertSnapshot(
                    of: controller,
                    as: .image(size: size),
                    named: choice.rawValue
                )
            }
        }
    }

    // MARK: - EverydaySeed content-first cards

    func test_everydaySeed_contentFirstCards() throws {
        defer { ThumbnailCache.shared.clear() }
        let ctx = try makeContext()
        let captures = SeedFixtures.captures(for: .everyday, now: Date(timeIntervalSince1970: 1_793_801_100))
        for (index, capture) in captures.enumerated() {
            let isPNG = capture.typeIdentifier == NSPasteboard.PasteboardType.png.rawValue
            let text = capture.payloadString ?? ""
            let type: ClipboardType
            var sensitivity: SensitivityCategory?
            if isPNG {
                type = .image
            } else if text.hasPrefix("#"), text.count == 7 {
                type = .color
            } else if text.hasPrefix("https://") {
                type = .url
            } else if text.hasPrefix("SELECT ") || text.hasPrefix("guard let ") {
                type = .code
            } else {
                type = .text
                if text.hasPrefix("sk-ant-") {
                    sensitivity = .apiKey
                }
            }
            let item = ClipboardItem(
                type: type,
                sourceBundleID: capture.frontmostBundleID,
                sourceAppName: capture.frontmostBundleID?.split(separator: ".").last.map(String.init),
                previewText: sensitivity != nil ? "sk-ant-••••••••••••" : text,
                sensitivity: sensitivity,
                sensitivityMaskedPreview: sensitivity != nil ? "sk-ant-••••••••••••" : nil,
                contentHash: capture.contentHash,
                byteSize: capture.payload.count,
                deviceID: "test-device",
                sequenceNumber: Int64(index + 1)
            )
            ctx.insert(item)
            if isPNG, let image = NSImage(data: capture.payload) {
                ThumbnailCache.shared.store(
                    .init(image: image, isAnimated: false, byteSize: capture.payload.count),
                    for: item.id
                )
            }
            snapshotCard(
                ClipboardCard(item: item, shortcutNumber: (index % 9) + 1),
                named: "clip-\(index)-\(type.rawValue)"
            )
        }
    }

    // MARK: - Pixel assertions (header wash contrast & 4/5/6-line footer clearance)

    private func renderAt2x(
        _ card: some View,
        cardSize: CGSize,
        padding: CGFloat = 20,
        theme: AppTheme,
        dark: Bool
    ) throws
    -> NSBitmapImageRep {
        let ground = Color(hex: theme.groundHex(dark: dark)) ?? .black
        let accent = Color.pestoAccent(stored: AccentChoice.defaultStored, theme: theme.rawValue)
        let root = card
            .defaultAppStorage(AppDefaults.store)
            .environment(\.pestoAccent, accent)
            .environment(\.shelfDrawsGlass, false)
            .preferredColorScheme(dark ? .dark : .light)
            .frame(width: cardSize.width, height: cardSize.height)
            .padding(padding)
            .background(ground)
        let controller = NSHostingController(rootView: root)
        controller.view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        controller.view.frame = NSRect(
            x: 0,
            y: 0,
            width: cardSize.width + 2 * padding,
            height: cardSize.height + 2 * padding
        )
        let bounds = controller.view.bounds
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(bounds.width * 2),
            pixelsHigh: Int(bounds.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        rep.size = bounds.size
        controller.view.cacheDisplay(in: bounds, to: rep)
        return rep
    }

    private func hexString(_ color: NSColor) -> String {
        func byte(_ value: CGFloat) -> String {
            String(format: "%02X", Int((value * 255).rounded()))
        }
        return byte(color.redComponent) + byte(color.greenComponent) + byte(color.blueComponent)
    }

    func test_whenHeaderWashDrawn_thenTopRegionTextContrastMeetsAA() throws {
        let ctx = try makeContext()
        let item = makeItem(in: ctx, type: .text, preview: "Header wash contrast check\nSecond line of text")
        item.customTitle = "Important Note"
        item.sourceAppName = "Safari"
        item.sourceDominantColorHex = "#1E88E5"
        let cardSize = CGSize(width: 200, height: 180)
        let padding: CGFloat = 20

        for theme in AppTheme.allCases {
            for dark in [false, true] {
                let rep = try renderAt2x(
                    ClipboardCard(item: item, shortcutNumber: 1),
                    cardSize: cardSize,
                    padding: padding,
                    theme: theme,
                    dark: dark
                )
                let scale = CGFloat(rep.pixelsWide) / (cardSize.width + 2 * padding)
                let bgSample = try XCTUnwrap(
                    rep.colorAt(
                        x: Int((padding + cardSize.width - 14) * scale),
                        y: Int((padding + 12) * scale)
                    )?.usingColorSpace(.sRGB)
                )
                let bgHex = hexString(bgSample)
                let xRange = Int((padding + 10) * scale)..<Int((padding + cardSize.width - 14) * scale)
                let yRange = Int((padding + 8) * scale)..<Int((padding + 32) * scale)
                var inkCandidates: [NSColor] = []
                for y in yRange {
                    for x in xRange {
                        guard let pixel = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                        if abs(pixel.brightnessComponent - bgSample.brightnessComponent) > 0.15 {
                            inkCandidates.append(pixel)
                        }
                    }
                }
                let strongestInk = try XCTUnwrap(
                    inkCandidates.max {
                        abs($0.brightnessComponent - bgSample.brightnessComponent)
                            < abs($1.brightnessComponent - bgSample.brightnessComponent)
                    },
                    "Expected top-region text pixels for \(theme.rawValue) \(dark ? "dark" : "light")"
                )
                let ratio = ContrastRatio.between(hexString(strongestInk), bgHex)
                XCTAssertGreaterThanOrEqual(
                    ratio,
                    4.5,
                    "Top-region text contrast \(ratio) below 4.5:1 on \(theme.rawValue) \(dark ? "dark" : "light")"
                )
            }
        }
    }

    func test_when4_5_6LineTextRendered_thenFooterClearanceIsPreserved() throws {
        let ctx = try makeContext()
        let padding: CGFloat = 20
        for width in [160, 200, 240] {
            let cardSize = CardMetrics.dimensions(width: width)
            try withCardWidth(width) {
                for lineCount in [4, 5, 6] {
                    let body = (1...lineCount).map { "Line \($0) clearance" }.joined(separator: "\n")
                    let item = makeItem(in: ctx, type: .text, preview: body)
                    item.sourceAppName = "Notes"
                    let rep = try renderAt2x(
                        ClipboardCard(item: item, shortcutNumber: 1),
                        cardSize: cardSize,
                        padding: padding,
                        theme: .basil,
                        dark: true
                    )
                    let scale = CGFloat(rep.pixelsWide) / (cardSize.width + 2 * padding)
                    let bgSample = try XCTUnwrap(
                        rep.colorAt(
                            x: Int((padding + cardSize.width - 14) * scale),
                            y: Int((padding + cardSize.height - 30) * scale)
                        )?.usingColorSpace(.sRGB)
                    )
                    let xRange = Int((padding + 12) * scale)..<Int((padding + cardSize.width - 12) * scale)
                    let clearanceTop = Int((padding + cardSize.height - 34) * scale)
                    let clearanceBottom = Int((padding + cardSize.height - 26) * scale)
                    var clearRows = 0
                    for y in clearanceTop..<clearanceBottom {
                        let hasInk = xRange.contains { x in
                            guard let pixel = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
                            return abs(pixel.brightnessComponent - bgSample.brightnessComponent) > 0.2
                        }
                        if !hasInk { clearRows += 1 }
                    }
                    XCTAssertGreaterThanOrEqual(
                        clearRows,
                        Int(4 * scale),
                        "Expected >= 4 pt clear gap above footer for \(lineCount) lines at width \(width)"
                    )
                }
            }
        }
    }
}
