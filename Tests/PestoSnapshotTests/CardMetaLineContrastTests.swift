// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftData
import SwiftUI
import XCTest
@testable import Pesto

/// D-07, after ADR 0044: the age in the line of facts at the foot of a card is quiet text on the card's own fill, which
/// sits on the shelf ground of the theme. Measured from the drawn card: the pixel furthest from the fill's colour in
/// that line is the text colour at full coverage, so the ratio is a little conservative.
@MainActor
final class CardMetaLineContrastTests: XCTestCase {
    private let cardSize = CGSize(width: 200, height: 180)
    private let padding: CGFloat = 20

    private func item() throws -> ClipboardItem {
        let ctx = try ModelContext(ModelContainerSetup.makeInMemory())
        let item = ClipboardItem(
            type: .text, sourceAppName: "Notes", previewText: "Quick brown fox", contentHash: UUID().uuidString,
            byteSize: 15, deviceID: "test-device", sequenceNumber: 1
        )
        ctx.insert(item)
        return item
    }

    private func hex(_ color: NSColor) -> String {
        func byte(_ value: CGFloat) -> String {
            String(format: "%02X", Int((value * 255).rounded()))
        }
        return byte(color.redComponent) + byte(color.greenComponent) + byte(color.blueComponent)
    }

    private func render(theme: AppTheme, dark: Bool) throws -> NSBitmapImageRep {
        let ground = Color(hex: theme.groundHex(dark: dark)) ?? .black
        let root = try ClipboardCard(item: item())
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
        // Drawn at 2x, as on a Retina display: a view outside a window draws at 1x, where 10 pt text set on a half
        // point never reaches full coverage and reads as a lighter colour than it is.
        let bounds = controller.view.bounds
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        rep.size = bounds.size
        controller.view.cacheDisplay(in: bounds, to: rep)
        return rep
    }

    private func pixel(_ rep: NSBitmapImageRep, _ column: Int, _ row: Int) -> NSColor? {
        rep.colorAt(x: column, y: row)?.usingColorSpace(.sRGB)
    }

    /// Right of the source tile, left of the trailing marks.
    private func ageColumns(scale: CGFloat) -> Range<Int> {
        Int((padding + 32) * scale)..<Int((padding + 110) * scale)
    }

    /// The pixel rows of the line of facts that hold text: they differ clearly in brightness from the card's fill.
    private func textRows(_ rep: NSBitmapImageRep, scale: CGFloat, background: CGFloat) -> [Int] {
        let columns = ageColumns(scale: scale)
        let bottom = padding + cardSize.height
        return (Int((bottom - 28) * scale)..<Int((bottom - 3) * scale)).filter { row in
            columns.contains { column in
                guard let color = pixel(rep, column, row) else { return false }
                return abs(color.brightnessComponent - background) > 0.2
            }
        }
    }

    /// The age is the last line of text on the card: the rows of the last unbroken run.
    private func lastRun(of rows: [Int]) -> [Int] {
        var run: [Int] = []
        for row in rows.reversed() {
            if let previous = run.last, previous - row > 1 { break }
            run.append(row)
        }
        return run
    }

    /// The contrast of the age against the card's fill, or nil when no text was found there.
    private func ageContrast(theme: AppTheme, dark: Bool) throws -> (ratio: Double, colors: String)? {
        let rep = try render(theme: theme, dark: dark)
        let scale = CGFloat(rep.pixelsWide) / (cardSize.width + 2 * padding)
        let column = Int((padding + cardSize.width - 12) * scale)
        let backgroundColor = try XCTUnwrap(pixel(rep, column, Int((padding + cardSize.height - 14) * scale)))
        let run = lastRun(of: textRows(rep, scale: scale, background: backgroundColor.brightnessComponent))
        let columns = ageColumns(scale: scale)
        let candidates = run.flatMap { row in columns.compactMap { pixel(rep, $0, row) } }
        let text = candidates.max {
            abs($0.brightnessComponent - backgroundColor.brightnessComponent)
                < abs($1.brightnessComponent - backgroundColor.brightnessComponent)
        }
        return text.map {
            (ContrastRatio.between(hex($0), hex(backgroundColor)), "\(hex($0)) on \(hex(backgroundColor))")
        }
    }

    func test_whenAnyThemeAndAppearance_thenTheAgeInTheLineOfFactsReads() throws {
        var report: [String] = []
        var failures: [String] = []
        for theme in AppTheme.allCases {
            for dark in [false, true] {
                let measured = try XCTUnwrap(ageContrast(theme: theme, dark: dark), "no age text found")
                let line = "\(theme) \(dark ? "dark" : "light"): " + String(format: "%.2f", measured.ratio)
                    + " (\(measured.colors))"
                report.append(line)
                if measured.ratio < 4.5 { failures.append(line) }
            }
        }
        add(XCTAttachment(string: report.joined(separator: "\n")))
        XCTAssertTrue(failures.isEmpty, "the age reads under 4.5:1 on: \(failures.joined(separator: "; "))")
    }
}
