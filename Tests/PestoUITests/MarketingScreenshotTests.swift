// SPDX-License-Identifier: MIT
import XCTest

/// The website's screenshots. Not part of the gate: run them with `make marketing-images`.
/// Each shot is taken in light and dark, over the branded backdrop, from the `marketing` seed.
final class MarketingScreenshotTests: PestoUITestCase {
    private let heroSize = CGSize(width: 1440, height: 810)
    private let tallSize = CGSize(width: 1200, height: 600)
    private let shortSize = CGSize(width: 1200, height: 400)
    private let largeShelfHeight: CGFloat = 292
    private let narrowSize = CGSize(width: 720, height: 560)

    private var backdropWindow: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "marketing-backdrop").firstMatch
    }

    private func settle(_ seconds: TimeInterval = 0.8) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// Launches over the backdrop in each appearance, runs the shot, and relaunches clean for the next one.
    private func inBothAppearances(
        backdrop: String = "plain", defaults: [String: String] = [:], _ shot: (String) throws -> Void
    ) throws {
        for mode in ["light", "dark"] {
            if mode == "dark" { app.terminate() }
            var launchDefaults = [
                "hasOnboarded": "true", "cardSize": "large", "accentColorHex": "brand",
                "linkPreviewsEnabled": "false", "appearanceMode": mode
            ]
            launchDefaults.merge(defaults) { _, new in new }
            launch(seed: "marketing", defaults: launchDefaults, backdrop: backdrop)
            XCTAssertTrue(backdropWindow.waitForExistence(timeout: 10), "the backdrop window never appeared")
            try shot(mode)
        }
    }

    /// Crops `region` (screen points) out of the backdrop's pixels, which include the shelf, popovers and menus above
    /// it, and attaches it as `<name>-<mode>@2x`.
    private func capture(_ name: String, mode: String, region: CGRect) {
        let backdrop = backdropWindow.frame
        let bounded = region.intersection(backdrop)
        let image = backdropWindow.screenshot().image
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return XCTFail("no pixels for \(name)")
        }
        let scale = CGFloat(cgImage.width) / backdrop.width
        let pixels = CGRect(
            x: ((bounded.minX - backdrop.minX) * scale).rounded(),
            y: ((bounded.minY - backdrop.minY) * scale).rounded(),
            width: (bounded.width * scale).rounded(), height: (bounded.height * scale).rounded()
        ).intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        guard let cropped = cgImage.cropping(to: pixels) else { return XCTFail("could not crop \(name)") }
        let attachment = XCTAttachment(image: NSImage(cgImage: cropped, size: .zero))
        attachment.name = "\(name)-\(mode)@2x"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// A strip anchored to the backdrop's bottom-left corner, which is where the shelf sits.
    private func bottomStrip(_ size: CGSize, originX: CGFloat = 0) -> CGRect {
        let backdrop = backdropWindow.frame
        let width = min(size.width, backdrop.width - originX)
        let height = min(size.height, backdrop.height)
        return CGRect(x: backdrop.minX + originX.rounded(), y: backdrop.maxY - height, width: width, height: height)
    }

    func test_hero() throws {
        try inBothAppearances(backdrop: "hero") { mode in
            showOverlay()
            parkPointer()
            settle()
            capture("hero", mode: mode, region: bottomStrip(heroSize))
            capture("hero-narrow", mode: mode, region: bottomStrip(narrowSize))
        }
    }

    func test_shelf() throws {
        try inBothAppearances { mode in
            showOverlay()
            overlay.typeKey(.rightArrow, modifierFlags: [])
            overlay.typeKey(.rightArrow, modifierFlags: [])
            settle(1.4)
            capture("01-shelf", mode: mode, region: bottomStrip(tallSize))
            // Zoomed detail for the wide, short shelf: three cards, kept as their own picture (a design review,
            // 2026-10).
            let shelfTop = backdropWindow.frame.maxY - largeShelfHeight
            capture(
                "01-detail-cards", mode: mode,
                region: CGRect(x: backdropWindow.frame.minX + 225, y: shelfTop + 55, width: 640, height: 200)
            )
            capture("01-shelf-narrow", mode: mode, region: bottomStrip(narrowSize))
        }
    }

    func test_search() throws {
        let themes = [
            ("basil", "02-search"),
            ("parmesan", "02-search-parmesan"),
            ("pineNut", "02-search-pine-nut"),
            ("mortar", "02-search-mortar")
        ]
        for (index, (theme, shotName)) in themes.enumerated() {
            if index > 0 { app.terminate() }
            try inBothAppearances(defaults: ["appTheme": theme]) { mode in
                showOverlay()
                element(AccessibilityID.searchButton).click()
                XCTAssertTrue(element(AccessibilityID.searchField).waitForExistence(timeout: 5), "no search field")
                overlay.typeText("garlic")
                XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))
                settle(1.5)
                // The shelf window is bottom-anchored and `largeShelfHeight` tall, so that is the crop: a taller one shows
                // backdrop above the search field. If the search field or the cards do not fit inside that window with the
                // search rows open, the app is clipping them and the picture would show it, so the test fails first.
                let panel = bottomStrip(CGSize(width: shortSize.width, height: largeShelfHeight))
                XCTAssertGreaterThanOrEqual(
                    element(AccessibilityID.searchField).frame.minY, panel.minY, "the search field is above the shelf"
                )
                XCTAssertLessThanOrEqual(
                    cards.firstMatch.frame.maxY, panel.maxY, "a card is cut off by the shelf with the search rows open"
                )
                capture(shotName, mode: mode, region: panel)
            }
        }
    }

    func test_ask() throws {
        try inBothAppearances { mode in
            showOverlay()
            element(AccessibilityID.searchButton).click()
            XCTAssertTrue(element(AccessibilityID.searchField).waitForExistence(timeout: 5), "no search field")
            overlay.typeText("links from today")
            let ask = element(AccessibilityID.askButton)
            XCTAssertTrue(ask.waitForExistence(timeout: 5), "the Ask button did not appear")
            ask.click()
            expectation(
                for: NSPredicate(format: "isSelected == true"),
                evaluatedWith: element(AccessibilityID.filterChip("Today"))
            )
            waitForExpectations(timeout: 10)
            XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))
            settle(1.5)
            capture("03-ask", mode: mode, region: bottomStrip(shortSize))
        }
    }

    func test_collections() throws {
        let themes = [
            ("basil", "04-collections"),
            ("parmesan", "04-collections-parmesan"),
            ("pineNut", "04-collections-pine-nut"),
            ("mortar", "04-collections-mortar")
        ]
        for (index, (theme, shotName)) in themes.enumerated() {
            if index > 0 { app.terminate() }
            try inBothAppearances(defaults: ["appTheme": theme]) { mode in
                showOverlay()
                element(AccessibilityID.collectionChip("Pesto night")).click()
                settle(1.2)
                let size = CGSize(width: shortSize.width, height: overlay.frame.height)
                capture(shotName, mode: mode, region: bottomStrip(size))
            }
        }
    }

    func test_secrets() throws {
        try inBothAppearances { mode in
            showOverlay()
            parkPointer()
            overlay.scroll(byDeltaX: -760, deltaY: 0)
            parkPointer()
            settle(1.4)
            capture("05-secrets", mode: mode, region: bottomStrip(shortSize))
        }
    }

    func test_lock() throws {
        try inBothAppearances(defaults: ["biometricLockEnabled": "true"]) { mode in
            showOverlay(expectingCards: false)
            XCTAssertTrue(element(AccessibilityID.lockOverlay).waitForExistence(timeout: 10))
            settle(1.2)
            let lock = element(AccessibilityID.lockOverlay).frame
            capture("06-lock", mode: mode, region: bottomStrip(shortSize, originX: lock.midX - 600))
        }
    }

    func test_privacyPane() throws {
        try inBothAppearances { mode in
            send(.openSettings)
            XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
            element(AccessibilityID.settingsSidebar("Privacy")).click()
            settle(1.5)
            capture("07-privacy-pane", mode: mode, region: settingsWindow.frame.insetBy(dx: -56, dy: -56))
        }
    }

    func test_smartClips() throws {
        try inBothAppearances { mode in
            showOverlay()
            let first = cards.firstMatch
            first.rightClick()
            XCTAssertTrue(app.menuItems["Add to Calendar"].waitForExistence(timeout: 10))
            settle()
            capture("09-smart-clips", mode: mode, region: bottomStrip(CGSize(width: 720, height: 680)))
        }
    }

    func test_themes() throws {
        let themes = [
            ("basil", "theme-basil"),
            ("parmesan", "theme-parmesan"),
            ("pineNut", "theme-pine-nut"),
            ("mortar", "theme-mortar")
        ]
        for (index, (theme, shotName)) in themes.enumerated() {
            if index > 0 { app.terminate() }
            try inBothAppearances(defaults: ["appTheme": theme]) { mode in
                showOverlay()
                parkPointer()
                settle(1.0)
                let size = CGSize(width: backdropWindow.frame.width, height: max(overlay.frame.height, 292))
                capture(shotName, mode: mode, region: bottomStrip(size))
            }
        }
    }
}
