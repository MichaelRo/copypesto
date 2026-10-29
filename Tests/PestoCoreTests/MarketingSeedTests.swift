// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Marketing seed")
struct MarketingSeedTests {
    private var texts: [String] {
        MarketingSeed.captures().compactMap(\.payloadString)
    }

    @Test("the shelf has the film's 8 clips on top of the 20 earlier ones, the masked card newest")
    func whenBuilt_thenPlannedClipsInOrder() {
        let captures = SeedFixtures.captures(for: .marketing)

        #expect(captures.count == 28)
        #expect(captures.last?.payloadString == LunchRushSeed.cardNumber)
        #expect(captures.last?.frontmostBundleID == "com.apple.Safari")
        #expect(captures.dropLast(8).last?.payloadString?.hasPrefix("Pesto night at Dana's") == true)
        #expect(captures.last?.timestamp ?? .distantPast > captures.first?.timestamp ?? .distantFuture)
    }

    @Test("only Apple's own apps are the source of any clip")
    func whenBuilt_thenOnlyAppleSources() {
        for capture in MarketingSeed.captures() {
            #expect(capture.frontmostBundleID?.hasPrefix("com.apple.") == true, "\(capture.frontmostBundleID ?? "nil")")
        }
    }

    @Test("no real-looking secret prefix, no real domain, and plain English only")
    func whenBuilt_thenNothingThatNamesAVendorOrAPerson() {
        let banned = ["sk-", "ghp_", "gho_", "ghs_", "AKIA", "ASIA", "xoxb-", "xoxp-", "github_pat_"]
        for text in texts + MarketingSeed.collectionRecords().flatMap(\.representations).compactMap(decoded) {
            for prefix in banned {
                #expect(!text.hasPrefix(prefix), Comment(rawValue: "\(prefix) in \(text)"))
            }
            let plain = text.unicodeScalars.allSatisfy(\.isASCII)
            #expect(plain, Comment(rawValue: "non-ASCII text: \(text)"))
        }
        for text in texts where text.hasPrefix("http") {
            #expect(
                text.hasPrefix("https://copypesto.net/") || text.hasPrefix("https://example.com/"),
                Comment(rawValue: text)
            )
        }
    }

    @Test("there is no parcel number, which would offer a real carrier")
    func whenBuilt_thenNoTrackingNumber() {
        #expect(!texts.contains { $0.range(of: #"^1Z[0-9A-Z]{16}$"#, options: .regularExpression) != nil })
    }

    @Test("two collections and a pinned thank-you snippet with a placeholder")
    func whenCollectionsBuilt_thenPestoNightAndRecipes() {
        let records = MarketingSeed.collectionRecords()

        #expect(Set(records.compactMap(\.pinboard)) == ["Pesto night", "Recipes"])
        let snippet = records.first { $0.title == "Thank you" }
        let snippetText = snippet?.representations.first.flatMap(decoded)
        #expect(snippetText?.contains("{{date}}") == true)
        #expect(records.allSatisfy { $0.timestamp < Date().addingTimeInterval(-86_400) }, "they sit at the end of All")
    }

    @Test("every seeded collection has its own icon and colour, so its chip is told apart from the others")
    func whenCollectionsBuilt_thenEachHasADistinctStyle() {
        let boards = Set(MarketingSeed.collectionRecords().compactMap(\.pinboard))
        let styles = boards.compactMap { MarketingSeed.collectionStyles[$0] }

        #expect(styles.count == boards.count)
        #expect(Set(styles.map(\.symbol)).count == boards.count)
        #expect(Set(styles.map(\.colorHex)).count == boards.count)
    }

    @Test(
        "the recipe card is a picture whose words can be read back, so searching for text in pictures works",
        .enabled(if: VisionAvailability.canRecognizeText, "text recognition needs a real Mac")
    )
    func whenRecipeCardRead_thenWordsFound() async throws {
        let card = try #require(MarketingSeed.captures().first { $0.payload == ShowcaseArt.recipeCard() }?.payload)

        let text = try #require(await OCRService().recognize(imageData: card))

        #expect(text.localizedCaseInsensitiveContains("garlic"))
        #expect(text.localizedCaseInsensitiveContains("basil"))
    }

    private func decoded(_ representation: PasteImportRecord.Representation) -> String? {
        Data(base64Encoded: representation.dataBase64).flatMap { String(data: $0, encoding: .utf8) }
    }

    @Test("every seeded collection has a style of its own, so the chips on the shelf do not look alike")
    func whenCollectionsSeeded_thenEachHasADistinctStyle() {
        let boards = Set(MarketingSeed.collectionRecords().compactMap(\.pinboard))
        let styles = boards.compactMap { MarketingSeed.collectionStyles[$0] }

        #expect(styles.count == boards.count, "a seeded collection has no style")
        #expect(Set(styles.map(\.symbol)).count == styles.count)
        #expect(Set(styles.map(\.colorHex)).count == styles.count)
    }
}
