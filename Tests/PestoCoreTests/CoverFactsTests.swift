// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("What a covered card still tells")
struct CoverFactsTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private struct Case {
        let name: String
        let item: ClipboardItem
        let forbidden: [String]
    }

    private func makeItem(
        _ type: ClipboardType, preview: String, source: String? = "Safari", bytes: Int = 4_200_000,
        secret: SensitivityCategory? = nil, mask: String? = nil, title: String? = nil, pinned: Bool = false
    )
    throws -> ClipboardItem {
        let container = try ModelContainerSetup.makeInMemory()
        let context = ModelContext(container)
        let item = ClipboardItem(
            type: type, sourceBundleID: "com.apple.Safari", sourceAppName: source, previewText: preview,
            sensitivity: secret, sensitivityMaskedPreview: mask, contentHash: UUID().uuidString, byteSize: bytes,
            deviceID: "t", sequenceNumber: 1, isPinned: pinned
        )
        item.timestamp = now.addingTimeInterval(-180)
        context.insert(item)
        if let title { item.customTitle = title }
        return item
    }

    private func cases() throws -> [Case] {
        try [
            Case(
                name: "credit card",
                item: makeItem(
                    .text, preview: "4242 4242 4242 4242", secret: .creditCard, mask: "•••• •••• •••• 4242"
                ),
                forbidden: ["4242", "Card", "card", "credit", "Safari", "4.2", "MB", "lock"]
            ),
            Case(
                name: "API key",
                item: makeItem(.text, preview: "sk_live_abcdef", secret: .apiKey, mask: "sk_live_••••"),
                forbidden: ["sk_live", "API", "key", "Key", "Safari", "Token", "token"]
            ),
            Case(
                name: "file with a revealing name",
                item: makeItem(.file, preview: "/Users/me/Taxes/Divorce-Settlement-2026.pdf"),
                forbidden: ["Divorce", "Settlement", "Taxes", ".pdf", "2026", "Safari", "4.2", "MB", "KB"]
            ),
            Case(
                name: "link",
                item: makeItem(.url, preview: "https://secret-clinic.example.com/results?id=9"),
                forbidden: ["secret-clinic", "example.com", "https", "results", "Safari"]
            ),
            Case(
                name: "color",
                item: makeItem(.color, preview: "#2F7A49"),
                forbidden: ["2F7A49", "#", "2f7a49", "green", "Safari"]
            ),
            Case(
                name: "pinned titled clip",
                item: makeItem(.text, preview: "launch codes", title: "Launch codes", pinned: true),
                forbidden: ["Launch", "launch", "codes", "pinned", "Pinned", "Safari"]
            ),
            Case(
                name: "picture",
                item: makeItem(.image, preview: "Screenshot 2026-11-03 at 9.41.12", source: "Preview"),
                forbidden: ["Screenshot", "2026-11-03", "9.41", "Preview", "MB", "4.2", "×"]
            )
        ]
    }

    @Test("for every kind of clip, nothing that identifies its content or origin can reach the cover or VoiceOver")
    func noForbiddenFactAppears() throws {
        for testCase in try cases() {
            let facts = CoverFacts(item: testCase.item, number: 3, inCollection: false, now: now)
            let everything = facts.everyString.joined(separator: " | ")
            for word in testCase.forbidden {
                #expect(!everything.contains(word), "\(testCase.name): \"\(word)\" appears in \(everything)")
            }
        }
    }

    @Test("a masked secret and any sensitive clip read as plain Text, with no category")
    func sensitiveReadsAsText() throws {
        let card = try makeItem(.text, preview: "x", secret: .creditCard, mask: "•••• 4242")
        let picture = try makeItem(.image, preview: "scan", secret: .ssn, mask: "•••")
        #expect(CoverFacts(item: card, number: 1, inCollection: false, now: now).kind == "Text")
        #expect(CoverFacts(item: picture, number: 1, inCollection: false, now: now).kind == "Text")
    }

    @Test("an ordinary clip shows its kind as one plain word, its number and its age")
    func ordinaryFacts() throws {
        let link = try makeItem(.url, preview: "https://example.com")
        let facts = CoverFacts(item: link, number: 4, inCollection: false, now: now)

        #expect(facts.kind == "Link")
        #expect(facts.numberLabel == "⌘4")
        #expect(facts.age == "3m ago")
        #expect(facts.spokenLabel == "link, hidden")
        #expect(facts.spokenValue == "command 4, 3 minutes ago")
    }

    @Test("every kind names itself by the ClipboardType vocabulary")
    func everyKindHasItsWord() throws {
        for type in ClipboardType.allCases {
            let item = try makeItem(type, preview: "x")
            #expect(CoverFacts(item: item, number: nil, inCollection: false, now: now).kind == type.presentation.label)
        }
    }

    @Test("a card past the ninth has no number, and says none")
    func noNumberPastNine() throws {
        let facts = try CoverFacts(item: makeItem(.text, preview: "x"), number: nil, inCollection: false, now: now)

        #expect(facts.numberLabel == nil)
        #expect(facts.spokenValue == "3 minutes ago")
    }

    @Test("inside a collection the age follows the first copy, like the card")
    func ageFollowsTheCollection() throws {
        let item = try makeItem(.text, preview: "x")
        item.bringToFront(at: now.addingTimeInterval(-60))
        #expect(CoverFacts(item: item, number: nil, inCollection: false, now: now).age == "1m ago")
        #expect(CoverFacts(item: item, number: nil, inCollection: true, now: now).age == "3m ago")
    }
}
