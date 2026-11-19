// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import SwiftData
import Testing
@testable import Pesto

@Suite("Clip titles on Mac cards in All vs collections")
@MainActor
struct ClipboardCardTitlesTests {
    private func makeItem(
        type: ClipboardType,
        preview: String,
        sourceAppName: String = "Safari",
        customTitle: String? = nil,
        ogTitle: String? = nil,
        ogSiteName: String? = nil
    ) throws
    -> ClipboardItem {
        let container = try ModelContainerSetup.makeInMemory()
        let context = ModelContext(container)
        let item = ClipboardItem(
            type: type,
            sourceAppName: sourceAppName,
            previewText: preview,
            contentHash: UUID().uuidString,
            byteSize: preview.utf8.count,
            deviceID: "test-device",
            sequenceNumber: 1
        )
        item.customTitle = customTitle
        item.ogTitle = ogTitle
        item.ogSiteName = ogSiteName
        context.insert(item)
        return item
    }

    @Test("in All, a link with ogTitle and customTitle keeps ogTitle on the face and customTitle in the foot line")
    func whenInAllLinkHasOGAndCustomTitle_thenOGWinsAndCustomStaysInFooter() throws {
        let item = try makeItem(
            type: .url,
            preview: "https://developer.apple.com/documentation/swiftui/view",
            customTitle: "SwiftUI View Docs",
            ogTitle: "View | Apple Developer Documentation",
            ogSiteName: "Apple Developer"
        )
        let card = ClipboardCard(item: item, inCollection: false)

        #expect(card.faceLinkTitle == "View | Apple Developer Documentation")
        #expect(!card.showsTitleOnCardFace)
        let lines = CardMetaLine.candidates(card.metaFacts)
        #expect(lines.first?.hasPrefix("SwiftUI View Docs") == true)
    }

    @Test("in a collection, a link with customTitle and ogTitle shows customTitle on the face and keeps the app")
    func whenInCollectionLinkHasOGAndCustomTitle_thenCustomTitleShowsOnFace() throws {
        let item = try makeItem(
            type: .url,
            preview: "https://developer.apple.com/documentation/swiftui/view",
            customTitle: "SwiftUI View Docs",
            ogTitle: "View | Apple Developer Documentation",
            ogSiteName: "Apple Developer"
        )
        let card = ClipboardCard(item: item, inCollection: true)

        #expect(card.faceLinkTitle == "SwiftUI View Docs")
        #expect(card.showsTitleOnCardFace)
        let lines = CardMetaLine.candidates(card.metaFacts)
        #expect(lines.first?.hasPrefix("Safari") == true)
        #expect(lines.allSatisfy { !$0.contains("SwiftUI View Docs") })
    }

    @Test("in a collection, a link with ogTitle only still shows ogTitle when link previews are off")
    func whenInCollectionLinkHasOGTitleOnlyAndPreviewsOff_thenOGTitleShows() throws {
        let item = try makeItem(
            type: .url,
            preview: "https://developer.apple.com/documentation/swiftui/view",
            customTitle: nil,
            ogTitle: "View | Apple Developer Documentation"
        )
        let card = ClipboardCard(item: item, previewsAllowed: false, inCollection: true)

        #expect(card.faceLinkTitle == "View | Apple Developer Documentation")
        #expect(card.usesRichURLBody)
        #expect(!card.showsTitleOnCardFace)
    }

    @Test("in a collection, a link with only customTitle shows its top title kicker even when previews are off")
    func whenInCollectionLinkHasCustomTitleOnly_thenShowsTopTitleKicker() throws {
        let item = try makeItem(
            type: .url,
            preview: "https://developer.apple.com/documentation/swiftui/view",
            customTitle: "SwiftUI View Docs"
        )
        let card = ClipboardCard(item: item, previewsAllowed: false, inCollection: true)

        #expect(card.showsTitleOnCardFace)
        #expect(card.showsTopTitleKicker)
        let lines = CardMetaLine.candidates(card.metaFacts)
        #expect(lines.first?.hasPrefix("Safari") == true)
    }

    @Test("a full-bleed link card never passes a duplicate title to contentFirstChrome")
    func whenFullBleedLinkCard_thenContentFirstChromeTitleIsNil() throws {
        let item = try makeItem(
            type: .url,
            preview: "https://developer.apple.com/documentation/swiftui/view",
            customTitle: "SwiftUI View Docs"
        )
        let card = ClipboardCard(item: item, inCollection: true)
        #expect(card.fullBleedLinkChromeTitle == nil)
    }

    @Test("concealed clips hide both customTitle and ogTitle inside a collection")
    func whenConcealedInCollection_thenTitlesHidden() throws {
        let item = try makeItem(
            type: .url,
            preview: "https://internal.example.com/secret",
            customTitle: "Internal Token",
            ogTitle: "Secret Page"
        )
        let card = ClipboardCard(item: item, isPrivacyBlurred: true, inCollection: true)

        #expect(card.trimmedCustomTitle == nil)
        #expect(card.trimmedOgTitle == nil)
        #expect(card.faceLinkTitle == nil)
        #expect(!card.showsTitleOnCardFace)
    }
}
