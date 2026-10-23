// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import Testing
@testable import Pesto

@Suite("What VoiceOver says about a card")
struct CardAccessibilityTests {
    private func card(
        type: ClipboardType = .text, source: String? = "Safari", preview: String = "hello",
        hidden: Bool = false, pinned: Bool = false, slot: Int? = nil, burns: Bool = false, expires: Date? = nil,
        tags: [String] = [], collection: String? = nil, remote: Bool = false, age: TimeInterval = 30,
        selected: Bool = false, title: String? = nil, secret: SensitivityCategory? = nil
    )
    -> CardAccessibility {
        CardAccessibility(
            type: type, sourceName: source, preview: preview, isHiddenSensitive: hidden, isPinned: pinned,
            hotkeySlot: slot, burnsAfterPaste: burns, expiresAt: expires, tags: tags, collectionName: collection,
            isRemote: remote, age: age, isSelected: selected, title: title, secretCategory: secret
        )
    }

    @Test("the label names the kind, the source and the text, in the form the UI tests and automation rely on")
    func label_isKindSourceAndText() {
        #expect(card().label == "text from Safari: hello")
        #expect(card(type: .url, preview: "https://example.com").label == "link from Safari: https://example.com")
        #expect(card(type: .color, source: nil, preview: "#529D6E").label == "color: #529D6E")
    }

    @Test("a hidden card says so and never reads its text")
    func label_hiddenNeverExposesText() {
        let spoken = card(preview: "4242 4242 4242 4242", hidden: true)

        #expect(spoken.label == "text from Safari: sensitive content, hidden")
        #expect(!spoken.label.contains("4242") && !spoken.value.contains("4242"))
    }

    @Test("a masked secret is read as its kind and what the mask keeps, not as one dot after another")
    func label_maskedSecretSaysItsKindAndNoDots() {
        let number = card(preview: "•••• •••• •••• 4242", secret: .creditCard)
        let key = card(preview: "ghp_•••••••••••• (45 characters hidden)", secret: .apiKey)

        #expect(number.label == "text from Safari: card number, hidden 4242")
        #expect(key.label == "text from Safari: API key, ghp_ hidden (45 characters hidden)")
        #expect(!number.label.contains("•") && !key.label.contains("•"))
    }

    @Test("a mask of nothing but dots is just hidden")
    func spokenMask_dotsOnly() {
        #expect(CardAccessibility.spokenMask("••••••••") == "hidden")
        #expect(CardAccessibility.spokenMask("Secret assignment (hidden)") == "Secret assignment (hidden)")
    }

    @Test("a long text is cut for the label but the full text is offered by the value only when short")
    func label_isCutAtAHundredAndTwentyCharacters() {
        let long = String(repeating: "a", count: 300)

        #expect(card(preview: long).label.count <= "text from Safari: ".count + 120)
    }

    @Test("a title the person gave the clip is spoken, in the value so the label stays what automation finds")
    func value_namesTheTitle() {
        let spoken = card(age: 30, title: "Quarterly figures")

        #expect(spoken.value.hasPrefix("named Quarterly figures"))
        #expect(!spoken.label.contains("Quarterly"))
        #expect(!card().value.contains("named"))
        #expect(!card(title: "  ").value.contains("named"))
    }

    @Test("the value carries everything the card shows that the label does not")
    func value_listsState() {
        let spoken = card(
            pinned: true, slot: 3, burns: true, tags: ["work", "pesto"], collection: "Recipes", remote: true,
            age: 300, selected: true
        )

        #expect(spoken.value == "pinned, control 3, burns after paste, 2 tags: work and pesto, in Recipes, "
            + "from another device, 5 minutes ago, selected")
    }

    @Test("nothing is invented: an ordinary card only says how old it is")
    func value_isMinimalForAnOrdinaryCard() {
        #expect(card(age: 30).value == "just now")
    }

    @Test("ages are spoken in words with correct plurals", arguments: [
        (30.0, "just now"), (60.0, "1 minute ago"), (120.0, "2 minutes ago"), (3600.0, "1 hour ago"),
        (7200.0, "2 hours ago"), (86_400.0, "1 day ago"), (172_800.0, "2 days ago")
    ])
    func spokenAge(seconds: Double, expected: String) {
        #expect(CardAccessibility.spokenAge(seconds) == expected)
    }

    @Test("one tag and one selected card read naturally")
    func value_singularForms() {
        #expect(card(tags: ["work"], age: 30).value == "1 tag: work, just now")
        #expect(card(age: 30, selected: true).value == "just now, selected")
    }
}
