// SPDX-License-Identifier: MIT
import XCTest

final class AnimatedGIFCardTests: PestoUITestCase {
    func test_gifCard_playsOnTheShelfWithoutHoverOrFocus() {
        launch(seed: "animated", motion: true)
        showOverlay()
        let gifCard = cards.matching(NSPredicate(format: "label CONTAINS[c] 'image'")).firstMatch
        XCTAssertTrue(gifCard.waitForExistence(timeout: 10), "no picture card on the shelf")

        var frames = Set<Data>()
        for _ in 0..<8 {
            frames.insert(gifCard.screenshot().pngRepresentation)
            Thread.sleep(forTimeInterval: 0.13)
        }
        XCTAssertGreaterThan(frames.count, 1, "the GIF card never changed: it is not playing")
    }

    /// A GIF copied as a file (Finder, Downloads) is a file clip, which showed a still icon.
    func test_gifFileCard_playsOnTheShelf() {
        launch(seed: "animated", motion: true)
        showOverlay()
        let fileCard = cards.matching(NSPredicate(format: "label CONTAINS[c] 'pesto-seed-dance.gif'")).firstMatch
        XCTAssertTrue(fileCard.waitForExistence(timeout: 10), "no card for the GIF file")

        var frames = Set<Data>()
        for _ in 0..<8 {
            frames.insert(fileCard.screenshot().pngRepresentation)
            Thread.sleep(forTimeInterval: 0.13)
        }
        XCTAssertGreaterThan(frames.count, 1, "the GIF file card never changed: it is not playing")
    }
}
