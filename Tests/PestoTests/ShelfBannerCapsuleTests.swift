// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import Testing
@testable import Pesto

@Suite("Shelf banners share one capsule geometry")
@MainActor
struct ShelfBannerCapsuleTests {
    private func size(of capsule: ShelfBannerCapsule) -> CGSize {
        NSHostingController(rootView: capsule).sizeThatFits(in: CGSize(width: 900, height: 100))
    }

    @Test("import offer, shelf suggestion and single-action banners share the 30 pt capsule height and fit their text")
    func whenBannersAreHosted_thenTheyShareTheCapsuleHeightAndDoNotClip() {
        var primaryFired = 0
        var secondaryFired = 0
        var dismissed = 0

        let importOffer = ShelfBannerCapsule(
            symbol: "square.and.arrow.down",
            message: "You have Paste on this Mac. Bring its history into Pesto?",
            primary: .init(title: "Import\u{2026}", identifier: "import-accept") { primaryFired += 1 },
            secondary: .init(title: "Not Now", identifier: "import-decline") { secondaryFired += 1 }
        )
        let suggestion = ShelfBannerCapsule(
            symbol: "pin",
            message: "You have pasted this clip 6 times. Pin it and paste it from any app with \u{2303}1?",
            primary: .init(title: "Pin with \u{2303}1", identifier: "suggestion-accept") { primaryFired += 1 },
            secondary: .init(title: "No Thanks", identifier: "suggestion-decline") { secondaryFired += 1 }
        )
        let dismissible = ShelfBannerCapsule(
            symbol: "hand.tap",
            message: "Double-click a card or press Return to paste it.",
            primary: .init(title: "Got It", identifier: "hint-accept") { primaryFired += 1 },
            onDismiss: { dismissed += 1 }
        )

        for banner in [importOffer, suggestion, dismissible] {
            let measured = size(of: banner)
            #expect(abs(measured.height - ShelfBannerCapsule.height) < 1, "banner height \(measured.height) != 30")
            #expect(measured.width > 220 && measured.width < 850, "unexpected banner width: \(measured.width)")
        }

        importOffer.primary.perform()
        suggestion.secondary?.perform()
        dismissible.onDismiss?()
        #expect(primaryFired == 1 && secondaryFired == 1 && dismissed == 1)
    }
}
