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

    /// A link to a GIF (copied from a browser's address bar or a chat) is a link clip whose picture is the GIF.
    func test_gifLinkCard_playsOnTheShelf() {
        launch(
            seed: "animated",
            defaults: ["hasOnboarded": "true", "linkPreviewsEnabled": "true"], motion: true, linkStubMillis: 50
        )
        showOverlay()
        let linkCard = cards.matching(NSPredicate(format: "label CONTAINS[c] 'pesto-link-dance'")).firstMatch
        XCTAssertTrue(linkCard.waitForExistence(timeout: 10), "no card for the GIF link")

        var frames = Set<Data>()
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline, frames.count < 2 {
            frames.insert(linkCard.screenshot().pngRepresentation)
            Thread.sleep(forTimeInterval: 0.13)
        }
        XCTAssertGreaterThan(frames.count, 1, "the GIF link card never changed: its picture is a still")
    }
}
