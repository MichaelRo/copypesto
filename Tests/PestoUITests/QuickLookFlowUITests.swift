// SPDX-License-Identifier: MIT
import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest

final class QuickLookFlowUITests: PestoUITestCase {
    private func seedFilesOnPasteboard() throws {
        let board = NSPasteboard(name: NSPasteboard.Name("io.pesto.uitest.\(session)"))

        // 1. Animated/static GIF
        let gifURL = workDirectory.appendingPathComponent("sample.gif")
        let gifData = makeTinyGIF()
        try gifData.write(to: gifURL)
        board.clearContents()
        board.setData(gifData, forType: NSPasteboard.PasteboardType("com.compuserve.gif"))
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))

        // 2. PDF
        let pdfURL = workDirectory.appendingPathComponent("sample.pdf")
        let pdfString = [
            "%PDF-1.4",
            "1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj",
            "2 0 obj<</Type/Pages/Count 1/Kids[3 0 R]>>endobj",
            "3 0 obj<</Type/Page/MediaBox[0 0 100 100]/Parent 2 0 R>>endobj",
            "xref\n0 4\n0000000000 65535 f \n0000000009 00000 n ",
            "0000000052 00000 n \n0000000101 00000 n ",
            "trailer<</Size 4/Root 1 0 R>>\nstartxref\n169\n%%EOF\n"
        ].joined(separator: "\n")
        let pdfData = Data(pdfString.utf8)
        try pdfData.write(to: pdfURL)
        board.clearContents()
        board.writeObjects([pdfURL as NSURL])
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))

        // 3. WebP
        let webpURL = workDirectory.appendingPathComponent("sample.webp")
        let webpBytes: [UInt8] = [
            0x52, 0x49, 0x46, 0x46, 0x1A, 0x00, 0x00, 0x00,
            0x57, 0x45, 0x42, 0x50, 0x56, 0x50, 0x38, 0x4C,
            0x0E, 0x00, 0x00, 0x00, 0x2F, 0x00, 0x00, 0x00,
            0x00, 0x07, 0x10, 0x11, 0x11, 0x88, 0x88, 0xFE, 0x07, 0x00
        ]
        try Data(webpBytes).write(to: webpURL)
        board.clearContents()
        board.writeObjects([webpURL as NSURL])
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))

        // 4. Two Finder files
        let fileA = workDirectory.appendingPathComponent("alpha.txt")
        let fileB = workDirectory.appendingPathComponent("beta.txt")
        try Data("alpha".utf8).write(to: fileA)
        try Data("beta".utf8).write(to: fileB)
        board.clearContents()
        board.writeObjects([fileA as NSURL, fileB as NSURL])
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
    }

    private func makeTinyGIF() -> Data {
        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            output, UTType.gif.identifier as CFString, 1, nil
        ) else {
            return Data()
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        if let ctx = CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let img = ctx.makeImage() {
            CGImageDestinationAddImage(dest, img, nil)
            CGImageDestinationFinalize(dest)
        }
        return output as Data
    }

    func test_whenUsingQuickLookWithCommandYAndEscape_thenPreviewOpensClosesAndStaysClosedOnArrows() throws {
        launch(seed: "empty")
        try seedFilesOnPasteboard()
        showOverlay()

        XCTAssertGreaterThanOrEqual(cards.count, 4, "expected seeded GIF, PDF, WebP, and Finder files")
        let baseWindowCount = app.windows.count

        // ⌘Y opens preview
        overlay.typeKey("y", modifierFlags: .command)
        let opened = NSPredicate { _, _ in self.app.windows.count > baseWindowCount }
        wait(for: [XCTNSPredicateExpectation(predicate: opened, object: nil)], timeout: 5)

        // Esc closes only preview; shelf stays open
        overlay.typeKey(.escape, modifierFlags: [])
        let closed = NSPredicate { _, _ in self.app.windows.count == baseWindowCount }
        wait(for: [XCTNSPredicateExpectation(predicate: closed, object: nil)], timeout: 5)
        XCTAssertTrue(overlay.exists, "Esc should close only Quick Look, leaving the shelf open")

        parkPointer()

        // Arrow keys move clips without reopening preview
        overlay.typeKey(.rightArrow, modifierFlags: [])
        overlay.typeKey(.rightArrow, modifierFlags: [])
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let qlPanels = app.windows.matching(NSPredicate(format: "title CONTAINS 'sample' OR title == 'Quick Look'"))
        XCTAssertEqual(qlPanels.count, 0, "arrow keys must not reopen Quick Look")

        // ⌘Y reopens preview on the newly focused clip
        overlay.typeKey("y", modifierFlags: .command)
        wait(for: [XCTNSPredicateExpectation(predicate: opened, object: nil)], timeout: 5)
    }
}
