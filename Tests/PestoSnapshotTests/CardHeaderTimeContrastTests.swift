// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftData
import SwiftUI
import XCTest
@testable import Pesto

/// D-07: the age under the app name is quiet text on the card's header tint, which sits on the shelf ground of the
/// theme. Measured from the drawn card: the pixel furthest from the header's own colour in the age line is the text
/// colour at full coverage, so the ratio is a little conservative.
@MainActor
final class CardHeaderTimeContrastTests: XCTestCase {
    private let cardSize = CGSize(width: 200, height: 180)
    private let padding: CGFloat = 20

    private func item(tint: String?) throws -> ClipboardItem {
        let ctx = try ModelContext(ModelContainerSetup.makeInMemory())
        let item = ClipboardItem(
            type: .text, sourceAppName: "Notes", previewText: "Quick brown fox", contentHash: UUID().uuidString,
            byteSize: 15, deviceID: "test-device", sequenceNumber: 1
        )
        item.sourceDominantColorHex = tint
        ctx.insert(item)
        return item
    }

    private func hex(_ color: NSColor) -> String {
        func byte(_ value: CGFloat) -> String {
            String(format: "%02X", Int((value * 255).rounded()))
        }
        return byte(color.redComponent) + byte(color.greenComponent) + byte(color.blueComponent)
    }

    private func render(theme: AppTheme, dark: Bool, tint: String?) throws -> NSBitmapImageRep {
        let ground = Color(hex: theme.groundHex(dark: dark)) ?? .black
        let root = try ClipboardCard(item: item(tint: tint))
            .environment(\.shelfDrawsGlass, false)
            .preferredColorScheme(dark ? .dark : .light)
            .frame(width: cardSize.width, height: cardSize.height)
            .padding(padding)
            .background(ground)
        let controller = NSHostingController(rootView: root)
        controller.view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        controller.view.frame = NSRect(
            x: 0, y: 0, width: cardSize.width + 2 * padding, height: cardSize.height + 2 * padding
        )
        let rep = try XCTUnwrap(controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds))
        controller.view.cacheDisplay(in: controller.view.bounds, to: rep)
        return rep
    }

    private func pixel(_ rep: NSBitmapImageRep, _ column: Int, _ row: Int) -> NSColor? {
        rep.colorAt(x: column, y: row)?.usingColorSpace(.sRGB)
    }

    /// The pixel rows of the header band that hold text: they differ clearly in brightness from the header.
    private func textRows(_ rep: NSBitmapImageRep, scale: CGFloat, background: CGFloat) -> [Int] {
        let columns = Int((padding + 40) * scale)..<Int((padding + cardSize.width - 40) * scale)
        return (Int((padding + 8) * scale)..<Int((padding + 62) * scale)).filter { row in
            columns.contains { column in
                guard let color = pixel(rep, column, row) else { return false }
                return abs(color.brightnessComponent - background) > 0.2
            }
        }
    }

    /// The age is the last line of text in the header: the rows of the last unbroken run.
    private func lastRun(of rows: [Int]) -> [Int] {
        var run: [Int] = []
        for row in rows.reversed() {
            if let previous = run.last, previous - row > 1 { break }
            run.append(row)
        }
        return run
    }

    /// The contrast of the age line against the header, or nil when no text was found there.
    private func ageContrast(theme: AppTheme, dark: Bool, tint: String?) throws -> Double? {
        let rep = try render(theme: theme, dark: dark, tint: tint)
        let scale = CGFloat(rep.pixelsWide) / (cardSize.width + 2 * padding)
        let column = Int((padding + cardSize.width - 12) * scale)
        let backgroundColor = try XCTUnwrap(pixel(rep, column, Int((padding + 30) * scale)))
        let run = lastRun(of: textRows(rep, scale: scale, background: backgroundColor.brightnessComponent))
        let columns = Int((padding + 40) * scale)..<Int((padding + cardSize.width - 40) * scale)
        let candidates = run.flatMap { row in columns.compactMap { pixel(rep, $0, row) } }
        let text = candidates.max {
            abs($0.brightnessComponent - backgroundColor.brightnessComponent)
                < abs($1.brightnessComponent - backgroundColor.brightnessComponent)
        }
        return text.map { ContrastRatio.between(hex($0), hex(backgroundColor)) }
    }

    func test_theAgeInTheHeader_readsOnEveryThemeAndHeaderColour() throws {
        var report: [String] = []
        var failures: [String] = []
        for theme in AppTheme.allCases {
            for dark in [false, true] {
                for tint in [nil, "D9A521", "3B82C4", "8A4F8F"] {
                    let ratio = try XCTUnwrap(ageContrast(theme: theme, dark: dark, tint: tint), "no age text found")
                    let line = "\(theme) \(dark ? "dark" : "light") \(tint ?? "plain"): "
                        + String(format: "%.2f", ratio)
                    report.append(line)
                    if ratio < 4.5 { failures.append(line) }
                }
            }
        }
        add(XCTAttachment(string: report.joined(separator: "\n")))
        XCTAssertTrue(failures.isEmpty, "the age reads under 4.5:1 on: \(failures.joined(separator: "; "))")
    }
}
