// SPDX-License-Identifier: MIT
import Foundation

/// The clips behind the website screenshots. Newest first here, as the shelf shows them.
/// In a Debug build (the one the screenshots are taken from) the film's first eight clips come first, as on the
/// website's demo shelf (copypesto-website, src/lib/shelf-demo.ts); a Release build keeps only the earlier set.
/// Every source is one of Apple's own apps, every address is example.com, and nothing is a real person, a real
/// secret or a parcel number (the Track action would name a real carrier).
public enum MarketingSeed {
    private enum Clip {
        case text(String, app: String)
        case picture(Data)
    }

    private static let messages = "com.apple.MobileSMS"
    private static let notes = "com.apple.Notes"
    private static let safari = "com.apple.Safari"
    private static let xcode = "com.apple.dt.Xcode"
    private static let terminal = "com.apple.Terminal"
    private static let colorSync = "com.apple.ColorSyncUtility"

    private static func newestFirst() -> [Clip] {
        [
            .text("Pesto night at Dana's, Friday at 7:00 pm. Bring the basil and pecorino.", app: messages),
            .picture(ShowcaseArt.basilLeaves()),
            .text("{ \"recipe\": \"pesto\",\n  \"servings\": 4 }", app: terminal),
            .text("Rule 1: Pine nuts must be toasted until golden, never scorched.", app: notes),
            .text("https://example.com/recipes/pesto-genovese", app: safari),
            .text("#2F7A49", app: colorSync),
            .text("Rosa's Deli, 123 Basil Lane. Call (555) 010-0142.", app: notes),
            .picture(ShowcaseArt.ingredientPalette()),
            .text("4242 4242 4242 4242", app: safari),
            .text(
                "1. Toast the pine nuts.\n2. Crush the basil, sea salt and garlic in a mortar.\n"
                    + "3. Drizzle Taggiasca olive oil.\n4. Fold in Parmigiano Reggiano last.",
                app: notes
            ),
            .text("https://copypesto.net/docs/shortcuts/", app: safari),
            .picture(ShowcaseArt.recipeCard()),
            .text("export PESTO_API_KEY=test_0000_not_a_real_key", app: terminal),
            .text(
                ":root {\n  --basil: #2F7A49;\n  --pine-nut: #EBD9B4;\n  --parmesan: #F6EFD9;\n  --mortar: #1F2320;\n}",
                app: xcode
            ),
            .text("git commit -m \"fix(sauce): remove heavy cream (closes #1: Italian blasphemy)\"", app: terminal),
            .text(
                "Shopping list: Genovese basil, pine nuts, garlic, Taggiasca oil, Parmigiano Reggiano, lemons.",
                app: notes
            ),
            .text("https://example.com/blog/why-pesto-is-o-n-log-n", app: safari),
            .text(
                "func scale(_ grams: Double, by servings: Int) -> Double {\n    grams * Double(servings) / 4\n}",
                app: xcode
            ),
            .picture(ShowcaseArt.pineNuts()),
            .text("#F2C14E", app: colorSync),
            .text("2 packed cups of Genovese basil is about 60 g. Pine nuts 50 g. Olive oil 100 ml.", app: notes)
        ]
    }

    /// Oldest first, which is the order `SeedFixtures` ingests in.
    public static func captures() -> [PasteboardCapture] {
        let earlier = newestFirst().reversed().map { clip in
            switch clip {
            case let .text(text, app): SeedFixtures.textCapture(text, app: app)
            case let .picture(data): SeedFixtures.pictureCapture(data)
            }
        }
        #if DEBUG
            // The film opens with the masked card, so the earlier set's own copy of that number is left out.
            let kept = earlier.filter { $0.payloadString != LunchRushSeed.cardNumber }
            return kept + LunchRushSeed.filmClips().reversed()
        #else
            return earlier
        #endif
    }

    /// The icon and colour of each seeded collection, so the shelf's chips tell the two apart.
    public static let collectionStyles: [String: (symbol: String, colorHex: String)] = [
        "Pesto night": ("party.popper", "#D94F5C"),
        "Recipes": ("fork.knife", "#5B8DEF")
    ]

    /// Two collections, imported pinned the way the first-run samples are, two days back so they sit at the end of All.
    public static func collectionRecords(now: Date = .now) -> [PasteImportRecord] {
        let then = now.addingTimeInterval(-2 * 86_400)
        func record(_ board: String, _ title: String?, _ text: String, _ offset: TimeInterval) -> PasteImportRecord {
            PasteImportRecord(
                pinboard: board, title: title, timestamp: then.addingTimeInterval(offset), sourceBundleID: notes,
                representations: [.init(
                    uti: "public.utf8-plain-text",
                    dataBase64: Data(text.utf8).base64EncodedString()
                )]
            )
        }
        return [
            record(
                "Pesto night", "Thank you",
                "Thanks for coming to pesto night on {{date}}. The recipe is below.\n\n{{cursor}}", 0
            ),
            record("Pesto night", nil, "Bring: basil, lemons, a hard cheese, bread.", -60),
            record("Pesto night", nil, "Seats: Dana, Sam, Priya, Lee.", -120),
            record(
                "Recipes", nil,
                "Pesto for four: basil 60 g, pine nuts 50 g, garlic 1 clove, oil 100 ml, cheese 40 g.", -180
            ),
            record("Recipes", nil, "Lemon basil dressing: 3 tbsp oil, 1 tbsp lemon, a pinch of salt.", -240)
        ]
    }
}
