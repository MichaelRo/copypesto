// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Lunch Rush seed")
struct LunchRushSeedTests {
    private var texts: [String] {
        LunchRushSeed.captures().compactMap(\.payloadString) + LunchRushSeed.snippets.map(\.text)
    }

    @Test("the six ingredients are the newest text clips, in the order they are copied")
    func whenBuilt_thenIngredientsAreNewestInOrder() {
        let newest = LunchRushSeed.captures().compactMap(\.payloadString).suffix(6)

        #expect(Array(newest) == LunchRushSeed.ingredients)
        #expect(LunchRushSeed.ingredients.count == 6)
    }

    @Test("every address is on example.com and every source is an Apple app")
    func whenBuilt_thenNoRealDomainOrSource() {
        for text in texts where text.contains("://") {
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

    @Test("the profile builds from the seed and ends on the ingredients")
    func whenProfileBuilt_thenIngredientsLast() {
        let captures = SeedFixtures.captures(for: .lunchRush)

        #expect(captures.suffix(6).compactMap(\.payloadString) == LunchRushSeed.ingredients)
        #expect(captures.contains { $0.payload == LunchRushSeed.sensitivePicture() })
    }
}
