// SPDX-License-Identifier: MIT
import Foundation

/// The clips behind the website's demo video, "The Lunch Rush". Nothing is real: Apple's own apps are the sources,
/// every
/// address is example.com, the card is the published test number and no clip says anything about health.
public enum LunchRushSeed {
    public struct Snippet: Sendable {
        public let title: String
        public let text: String
        public let shortcut: Int
    }

    public struct Link: Sendable {
        public let title: String
        public let url: String
    }

    public static let cardNumber = "4242 4242 4242 4242"
    public static let supplierCollection = "Supplier links"

    public static let ingredients = [
        "2 cups basil", "1 cup parmesan", "1/2 cup pine nuts", "1/2 cup olive oil", "2 cloves garlic", "a pinch of salt"
    ]

    public static let snippets = [
        Snippet(title: "Restart staging", text: "kubectl rollout restart deploy/basil-api -n staging", shortcut: 1),
        Snippet(
            title: "Order reply",
            text: #"Thanks {{input:Name}}, your order of {{input:Jars}} jars ships "#
                + #"{{choice:Day options="Thursday|Friday"}}."#,
            shortcut: 2
        ),
        Snippet(
            title: "Failing test",
            text: #"Write a failing test for {{input:Function}} that reproduces "#
                + #"{{input:Ticket default="PEST-142"}}. Do not fix it."#,
            shortcut: 3
        )
    ]

    public static let supplierLinks = [
        Link(title: "Supplier portal", url: "https://example.com/supplier/portal"),
        Link(title: "Invoice template", url: "https://example.com/invoices/template"),
        Link(title: "Health inspection checklist", url: "https://example.com/kitchen/inspection-checklist"),
        Link(title: "Lunch rota", url: "https://example.com/team/lunch-rota")
    ]

    public static func sensitivePicture() -> Data {
        ShowcaseArt.pestoBowl()
    }

    private static let notes = "com.apple.Notes"
    private static let safari = "com.apple.Safari"
    private static let messages = "com.apple.MobileSMS"

    /// Oldest first, which is the order `SeedFixtures` ingests in; the six ingredients are the newest.
    static func captures() -> [PasteboardCapture] {
        var captures: [PasteboardCapture] = []
        let chatter: [(String, String)] = [
            ("Wi-Fi password: ask Gary", messages),
            ("Meeting could have been this clip.", notes),
            ("v2_final_FINAL_use-this-one.docx", notes),
            ("Reading list: 212 tabs, 3 read", safari),
            ("Sorry for the late reply, I was copying.", notes),
            ("Order #4417: one jar, no questions", messages),
            ("Does it keep? Ask the jar.", messages),
            ("Yes. The pine nut supplier passed the September audit.", messages),
            ("Standup is at 9:15, bring basil.", messages)
        ]
        captures += chatter.map { SeedFixtures.textCapture($0.0, app: $0.1) }
        captures += supplierLinks.map { SeedFixtures.textCapture($0.url, app: safari) }
        captures.append(SeedFixtures.pictureCapture(sensitivePicture()))
        captures.append(SeedFixtures.textCapture(cardNumber, app: safari))
        captures += ingredients.map { SeedFixtures.textCapture($0, app: notes) }
        return captures
    }
}
