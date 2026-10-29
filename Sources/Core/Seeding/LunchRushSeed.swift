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
    public static let trackingNumber = "1Z999AA10123456784"
    public static let flightClip = "Flight PS 142 \u{00B7} Gate B7 \u{00B7} boards 14:05"
    public static let oilLink = "https://example.com/oil/cold-pressed"
    public static let garlicLine = "garlic.cloves = 2"

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
            title: "Order update",
            text: "Your pesto ships {{date+3d}}. Tracking: {{clipboard}}{{cursor}}",
            shortcut: 5
        ),
        Snippet(title: "Quick thanks", text: "Thanks, I\u{2019}ll get back to you today.", shortcut: 4),
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
        ShowcaseArt.pestoSpoon()
    }

    private static let notes = "com.apple.Notes"
    private static let safari = "com.apple.Safari"
    private static let messages = "com.apple.MobileSMS"

    /// Oldest first, which is the order `SeedFixtures` ingests in.
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
            (flightClip, messages),
            ("Standup is at 9:15, bring basil.", messages)
        ]
        captures += chatter.map { SeedFixtures.textCapture($0.0, app: $0.1) }
        captures += supplierLinks.map { SeedFixtures.textCapture($0.url, app: safari) }
        captures += richClips().reversed()
        return captures
    }

    /// Newest first, as the shelf shows them: the masked card and the covered picture open it, then a GIF, a video, a
    /// PDF
    /// and the rest of the kinds. The six ingredients are not here: the finale copies them live.
    private static func richClips() -> [PasteboardCapture] {
        let gif = LunchRushMedia.pestoGIF
        var clips: [PasteboardCapture] = [
            SeedFixtures.textCapture(cardNumber, app: safari),
            SeedFixtures.pictureCapture(sensitivePicture()),
            PasteboardCapture(
                typeIdentifier: "com.compuserve.gif", payload: gif, frontmostBundleID: safari,
                contentHash: SeedFixtures.hash(of: gif)
            )
        ]
        if let video = LunchRushMedia.bowlVideo { clips.append(SeedFixtures.fileCapture([video.path])) }
        if let pdf = LunchRushMedia.recipePDF { clips.append(SeedFixtures.fileCapture([pdf.path])) }
        clips += [
            SeedFixtures.pictureCapture(ShowcaseArt.basilLeaves()),
            SeedFixtures.textCapture("#2F7A49", app: "com.apple.ColorSyncUtility"),
            SeedFixtures.textCapture("\u{1F33F}\u{1F9C4}\u{1F9C0} Pesto night!", app: messages),
            SeedFixtures.textCapture(
                "## Pesto for four\n\n- **60 g** basil\n- **50 g** pine nuts\n- 1 clove garlic\n\n"
                    + "Toast the nuts first.",
                app: notes
            ),
            SeedFixtures.pictureCapture(ShowcaseArt.recipeCard()),
            SeedFixtures.textCapture(
                "func scale(_ grams: Double, by servings: Int) -> Double {\n    grams * Double(servings) / 4\n}",
                app: "com.apple.dt.Xcode"
            ),
            SeedFixtures.textCapture(oilLink, app: safari),
            SeedFixtures.textCapture(garlicLine, app: "com.apple.dt.Xcode"),
            SeedFixtures.textCapture("{ \"recipe\": \"pesto\",\n  \"servings\": 4 }", app: "com.apple.Terminal"),
            SeedFixtures.pictureCapture(ShowcaseArt.pineNuts()),
            SeedFixtures.textCapture("#EBD9B4", app: "com.apple.ColorSyncUtility")
        ]
        return clips
    }
}
