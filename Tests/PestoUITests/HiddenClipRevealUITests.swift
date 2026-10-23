// SPDX-License-Identifier: MIT
import XCTest

final class HiddenClipRevealUITests: PestoUITestCase {
    private let secret = "4242 4242 4242 4242"

    private func openShelf(authenticationGranted: Bool) {
        launch(defaults: [
            "hasOnboarded": "true",
            "uitestAuthenticationGranted": authenticationGranted ? "true" : "false"
        ])
        showOverlay()
    }

    private var maskedCard: XCUIElement {
        card(containing: "4242")
    }

    func test_aMaskedClip_isShownForAFewSeconds_afterAuthentication() {
        openShelf(authenticationGranted: true)
        XCTAssertTrue(maskedCard.waitForExistence(timeout: 10), "no masked card on the shelf")
        XCTAssertFalse(
            (maskedCard.value as? String ?? "").contains(secret),
            "the secret is readable before anyone asked"
        )

        maskedCard.rightClick()
        app.menuItems["Show"].click()

        let shown = NSPredicate { _, _ in (self.maskedCard.value as? String ?? "").contains(self.secret) }
        wait(for: [XCTNSPredicateExpectation(predicate: shown, object: nil)], timeout: 5)
        capture("hidden-clip-revealed")

        maskedCard.rightClick()
        app.menuItems["Hide"].click()
        let hidden = NSPredicate { _, _ in !(self.maskedCard.value as? String ?? "").contains(self.secret) }
        wait(for: [XCTNSPredicateExpectation(predicate: hidden, object: nil)], timeout: 5)
    }

    func test_aMaskedClip_staysHidden_whenAuthenticationIsRefused() {
        openShelf(authenticationGranted: false)
        XCTAssertTrue(maskedCard.waitForExistence(timeout: 10))

        maskedCard.rightClick()
        app.menuItems["Show"].click()
        RunLoop.current.run(until: Date().addingTimeInterval(2))

        XCTAssertFalse(
            (maskedCard.value as? String ?? "").contains(secret), "the clip was shown without authentication"
        )
    }
}
