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

    private func makeItem(
        type: ClipboardType,
        preview: String,
        textLength: Int? = nil,
        note: String? = nil,
        ogTitle: String? = nil,
        ogSiteName: String? = nil,
        customTitle: String? = nil,
        sensitivity: SensitivityCategory? = nil
    )
    -> ClipboardItem {
        let item = ClipboardItem(
            type: type,
            sourceAppName: "Safari",
            previewText: preview,
            sensitivity: sensitivity,
            contentHash: UUID().uuidString,
            byteSize: preview.utf8.count,
            deviceID: "test-device",
            sequenceNumber: 1
        )
        item.textLength = textLength ?? preview.count
        item.userNote = note
        item.ogTitle = ogTitle
        item.ogSiteName = ogSiteName
        item.customTitle = customTitle
        return item
    }

    @Test("VoiceOverDetails populates Details, Text, Title, Note, Files, and Text in the picture by clip kind")
    func voiceOverContent_coversAllClipKindsAndFields() {
        let textItem = makeItem(type: .text, preview: "Hello world", note: "Keep this")
        let textDetails = VoiceOverDetails.make(
            for: textItem, collectionName: "Notes", isBlurredAsSensitive: false, isCoveredForPrivacy: false
        )
        #expect(!textDetails.details.isEmpty)
        #expect(textDetails.text == "Hello world")
        #expect(textDetails.note == "Keep this")
        #expect(textDetails.title.isEmpty)
        #expect(textDetails.files.isEmpty)
        #expect(textDetails.inPicture.isEmpty)

        let codeItem = makeItem(type: .code, preview: "let x = 1", textLength: 501)
        let codeDetails = VoiceOverDetails.make(
            for: codeItem, collectionName: nil, isBlurredAsSensitive: false, isCoveredForPrivacy: false
        )
        #expect(!codeDetails.details.isEmpty)
        #expect(!codeDetails.details.contains("lines"))
        #expect(codeDetails.text.hasSuffix(" … Quick Look shows the rest."))

        let urlItem = makeItem(
            type: .url, preview: "https://example.com", ogTitle: "Example", ogSiteName: "Example Site"
        )
        let urlDetails = VoiceOverDetails.make(
            for: urlItem, collectionName: nil, isBlurredAsSensitive: false, isCoveredForPrivacy: false
        )
        #expect(urlDetails.title == "Example, Example Site")
        #expect(urlDetails.text == "https://example.com")

        let fileURLs = (1...8).map { "file:///tmp/file-\($0).txt" }.joined(separator: "\n")
        let fileItem = makeItem(type: .file, preview: fileURLs)
        let fileDetails = VoiceOverDetails.make(
            for: fileItem, collectionName: nil, isBlurredAsSensitive: false, isCoveredForPrivacy: false
        )
        #expect(fileDetails.files == "file-1.txt, file-2.txt, file-3.txt, file-4.txt, file-5.txt, file-6.txt")

        let longOCR = "  \n" + String(repeating: "A", count: 350) + "\n  "
        let imageItem = makeItem(type: .image, preview: longOCR)
        let imageDetails = VoiceOverDetails.make(
            for: imageItem, collectionName: nil, isBlurredAsSensitive: false, isCoveredForPrivacy: false
        )
        #expect(imageDetails.inPicture == String(repeating: "A", count: 300))

        let colorItem = makeItem(type: .color, preview: "#529D6E", note: "Brand green")
        let colorDetails = VoiceOverDetails.make(
            for: colorItem, collectionName: nil, isBlurredAsSensitive: false, isCoveredForPrivacy: false
        )
        #expect(!colorDetails.details.isEmpty)
        #expect(colorDetails.note == "Brand green")
        #expect(colorDetails.text.isEmpty)
        #expect(colorDetails.title.isEmpty)
        #expect(colorDetails.files.isEmpty)
        #expect(colorDetails.inPicture.isEmpty)
    }

    @Test("VoiceOverDetails truncates long text at CardPreviewText.previewLength")
    func voiceOverContent_truncatesLongText() {
        let longText = String(repeating: "b", count: CardPreviewText.previewLength + 25)
        let item = makeItem(type: .text, preview: longText, textLength: longText.count)
        let details = VoiceOverDetails.make(
            for: item, collectionName: nil, isBlurredAsSensitive: false, isCoveredForPrivacy: false
        )
        let expectedPrefix = String(repeating: "b", count: CardPreviewText.previewLength)
        #expect(details.text == expectedPrefix + " … Quick Look shows the rest.")
    }

    @Test("VoiceOverDetails clears sensitive or covered content while keeping Details")
    func voiceOverContent_clearsWhenSensitiveOrCovered() {
        let urlItem = makeItem(
            type: .url, preview: "https://secret.example.com", note: "Private note",
            ogTitle: "Secret", ogSiteName: "Internal"
        )
        let sensitiveItem = makeItem(
            type: .text, preview: "4242", note: "Card", sensitivity: .creditCard
        )

        for (item, blurred, covered) in [
            (sensitiveItem, false, false),
            (urlItem, true, false),
            (urlItem, false, true)
        ] {
            let details = VoiceOverDetails.make(
                for: item, collectionName: nil, isBlurredAsSensitive: blurred, isCoveredForPrivacy: covered
            )
            #expect(!details.details.isEmpty)
            #expect(details.note.isEmpty)
            #expect(details.text.isEmpty)
            #expect(details.title.isEmpty)
            #expect(details.files.isEmpty)
            #expect(details.inPicture.isEmpty)
        }
    }
}
