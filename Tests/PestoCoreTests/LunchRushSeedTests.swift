// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Lunch Rush seed")
struct LunchRushSeedTests {
    private var texts: [String] {
        LunchRushSeed.captures().compactMap(\.payloadString) + LunchRushSeed.snippets.map(\.text)
    }

    @Test("the six ingredients are not on the shelf at the start: the finale copies them live")
    func whenBuilt_thenIngredientsAreNotSeeded() {
        let texts = LunchRushSeed.captures().compactMap(\.payloadString)

        #expect(LunchRushSeed.ingredients.count == 6)
        #expect(LunchRushSeed.ingredients.allSatisfy { !texts.contains($0) })
    }

    @Test("every address is on example.com and every source is an Apple app")
    func whenBuilt_thenNoRealDomainOrSource() {
        for text in texts where text.contains("://") && !text.hasPrefix("file://") {
            #expect(text.hasPrefix("https://example.com/"), Comment(rawValue: text))
        }
        for capture in LunchRushSeed.captures() {
            #expect(capture.frontmostBundleID?.hasPrefix("com.apple.") == true)
        }
    }

    @Test("no health, allergen or vendor wording in any clip or title")
    func whenBuilt_thenNoHealthWords() {
        let banned = ["allerg", "vegan", "gluten", "nut-free", "safe to eat", "healthy", "cure", "diet", "sk-", "ghp_"]
        let all = texts + LunchRushSeed.snippets.map(\.title) + LunchRushSeed.supplierLinks.map(\.title)
        for text in all {
            for word in banned {
                #expect(!text.lowercased().contains(word), Comment(rawValue: "\(word) in \(text)"))
            }
        }
    }

    @Test("exactly one clip answers a search for audit")
    func whenSearchedForAudit_thenOneClip() {
        let matches = texts.filter { $0.lowercased().contains("audit") }

        #expect(matches == ["Yes. The pine nut supplier passed the September audit."])
    }

    @Test("snippets use the real fill-in syntax and a free ⌃ shortcut each")
    func whenSnippetsBuilt_thenRealSyntaxAndDistinctShortcuts() {
        let order = LunchRushSeed.snippets.first { $0.title == "Order reply" }

        #expect(order?.text.contains("{{input:Name}}") == true)
        #expect(order?.text.contains(#"{{choice:Day options="Thursday|Friday"}}"#) == true)
        let shortcuts = LunchRushSeed.snippets.map(\.shortcut)
        #expect(Set(shortcuts).count == shortcuts.count)
        #expect(shortcuts.allSatisfy { (1...9).contains($0) })
        #expect(LunchRushSeed.snippets.contains { $0.text.contains(#"{{input:Ticket default="PEST-142"}}"#) })
    }

    @Test("the card number is the published test number and the supplier links are four")
    func whenBuilt_thenCardAndLinks() {
        #expect(texts.contains("4242 4242 4242 4242"))
        #expect(LunchRushSeed.supplierLinks.count == 4)
    }

    @Test(
        "the shelf holds a clip of every kind: pictures, a GIF, a PDF, a video, a colour, an emoji and a quick snippet"
    )
    func whenBuilt_thenEveryKindIsThere() {
        let captures = LunchRushSeed.captures()
        let types = Set(captures.map(\.typeIdentifier))

        #expect(types.contains("com.compuserve.gif"))
        #expect(captures
            .contains { $0.payloadString?.hasSuffix(".pdf") == true || $0.payloadString?.contains(".pdf") == true })
        #expect(captures.contains { $0.payloadString?.contains(".mp4") == true })
        #expect(captures.contains { $0.payloadString?.hasPrefix("#2F7A49") == true })
        #expect(captures.contains { $0.payloadString?.unicodeScalars.contains { $0.value > 0x1F000 } == true })
        #expect(LunchRushSeed.snippets.contains { $0.title == "Quick thanks" && !$0.text.contains("{{") })
    }

    @Test("the shelf opens on the masked card, then the covered picture, then the GIF")
    func whenProfileBuilt_thenRichClipsAreNewest() {
        let captures = SeedFixtures.captures(for: .lunchRush)

        #expect(captures.last?.payloadString == LunchRushSeed.cardNumber)
        #expect(captures.dropLast().last?.payload == LunchRushSeed.sensitivePicture())
        #expect(captures.dropLast(2).last?.typeIdentifier == "com.compuserve.gif")
    }

    @Test("exactly one clip answers a search for flight")
    func whenSearchedForFlight_thenOneClip() {
        let matches = texts.filter { $0.lowercased().contains("flight") }

        #expect(matches == [LunchRushSeed.flightClip])
    }

    @Test("the order update snippet fills itself in from the date, the clipboard and the cursor, with no questions")
    func whenOrderUpdateBuilt_thenItAsksNothing() {
        let update = LunchRushSeed.snippets.first { $0.title == "Order update" }

        #expect(update?.text == "Your pesto ships {{date+3d}}. Tracking: {{clipboard}}{{cursor}}")
        #expect(update?.text.contains("{{input") == false)
        #expect(update?.text.contains("{{choice") == false)
    }

    @Test("the tracking number is a carrier example number, copied live and not seeded")
    func whenBuilt_thenTrackingNumberIsNotSeeded() {
        #expect(LunchRushSeed.trackingNumber == "1Z999AA10123456784")
        #expect(!texts.contains(LunchRushSeed.trackingNumber))
    }

    @Test("the finale kinds: a link and a line of code are seeded")
    func whenBuilt_thenFinaleKindsAreSeeded() {
        let texts = LunchRushSeed.captures().compactMap(\.payloadString)

        #expect(texts.contains(LunchRushSeed.oilLink))
        #expect(texts.contains(LunchRushSeed.garlicLine))
        #expect(LunchRushSeed.oilLink.hasPrefix("https://example.com/"))
    }
}
