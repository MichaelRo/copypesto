// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import PestoCore
@testable import PestoMobile

@Suite("Which face a clip's card takes")
struct CardFaceTests {
    private func face(
        _ type: ClipboardType, _ text: String = "", aspect: Double? = nil, animated: Bool = false,
        linkPicture: Bool = false, concealed: Bool = false, secret: Bool = false
    )
    -> CardFace {
        CardFace.decide(.init(
            type: type, text: text, isConcealed: concealed, isSecret: secret, pictureAspect: aspect,
            isAnimated: animated, hasLinkPicture: linkPicture
        ))
    }

    @Test("a covered clip shows nothing of itself, whatever its kind, and says whether it is a secret")
    func whenConcealed_thenCovered() {
        #expect(face(.text, "ghp_secret", concealed: true, secret: true) == .covered(isSecret: true))
        #expect(face(.image, aspect: 1, concealed: true) == .covered(isSecret: false))
        #expect(face(.color, "#3F7D4E", concealed: true) == .covered(isSecret: false))
    }

    @Test("a secret after Show is its own face, never a large-text or link card of the mask")
    func whenASecretIsShown_thenItKeepsTheSecretFace() {
        #expect(face(.text, "•••• 4242", secret: true) == .shownSecret)
    }

    @Test("a picture fills the card only near the card's shape (ADR 0041)", arguments: [0.8, 1.0, 1.11, 1.35])
    func whenPictureIsNearTheCardsShape_thenItFills(aspect: Double) {
        #expect(face(.image, aspect: aspect) == .picture(fillsCard: true, isAnimated: false))
    }

    @Test("a wide, tall or unmeasured picture is shown whole", arguments: [0.5625, 0.79, 1.36, 1.5, 1.78, nil])
    func whenPictureIsFarFromTheCardsShape_thenItIsShownWhole(aspect: Double?) {
        #expect(face(.image, aspect: aspect) == .picture(fillsCard: false, isAnimated: false))
    }

    @Test("a GIF keeps its badge on either path")
    func whenAnimated_thenTheFaceSaysSo() {
        #expect(face(.image, aspect: 1, animated: true) == .picture(fillsCard: true, isAnimated: true))
        #expect(face(.image, aspect: 2, animated: true) == .picture(fillsCard: false, isAnimated: true))
    }

    @Test("a color fills its card, with the ink Core picks for contrast")
    func whenColor_thenTheCardIsTheColorWithReadableInk() {
        guard case let .color(_, darkInk) = face(.color, "#2F7A49") else {
            Issue.record("a color clip is a color card")
            return
        }
        #expect(darkInk == .white)
        guard case let .color(_, lightInk) = face(.color, "#F6EFD9") else {
            Issue.record("a color clip is a color card")
            return
        }
        #expect(lightInk == .black)
    }

    @Test("short text is set large in Core's two sizes; longer or multi-line text is body text")
    func whenText_thenCoreDecidesTheSize() {
        #expect(face(.text, "Gate B7") == .largeText(points: CardTreatment.headlinePoints))
        #expect(face(.text, "Bring the basil and the pecorino") == .largeText(points: CardTreatment.secondaryPoints))
        #expect(face(.text, "first line\nsecond line") == .text)
        #expect(face(.text, String(repeating: "long ", count: 20)) == .text)
    }

    @Test("a link leads with its host, unless it has a stored preview picture")
    func whenLink_thenHostFirstOrItsPicture() {
        let link = LinkDisplay(host: "copypesto.net", rest: "/guide/")
        #expect(face(.url, "https://copypesto.net/guide/") == .link(link))
        #expect(face(.url, "https://copypesto.net/guide/", linkPicture: true) == .linkPicture)
    }

    @Test("code and files keep their own faces")
    func whenCodeOrFile_thenTheirOwnFaces() {
        #expect(face(.code, "let pesto = blend(basil)") == .code)
        #expect(face(.file, "file:///Users/me/recipe.pdf") == .file)
    }

    @Test("in All, no clip shows a title on the card face")
    func whenInAll_thenNoFaceTitle() {
        for type in [ClipboardType.text, .code, .file, .color, .image, .url] {
            let title = CardFace.faceTitle(
                type: type,
                inCollection: false,
                isConcealed: false,
                customTitle: "My Title",
                ogTitle: "Page Title"
            )
            #expect(title == nil)
            #expect(!CardFace.showsCustomTitleOnFace(inCollection: false, isConcealed: false, customTitle: "My Title"))
        }
    }

    @Test("in a collection, every non-concealed clip with a custom title shows it on the face")
    func whenInCollectionWithCustomTitle_thenShownOnFace() {
        for type in [ClipboardType.text, .code, .file, .color, .image, .url] {
            let title = CardFace.faceTitle(
                type: type,
                inCollection: true,
                isConcealed: false,
                customTitle: "  My Title  ",
                ogTitle: "Page Title"
            )
            #expect(title == "My Title")
            #expect(
                CardFace.showsCustomTitleOnFace(inCollection: true, isConcealed: false, customTitle: "  My Title  ")
            )
        }
    }

    @Test("in a collection, a link without a custom title falls back to its page title")
    func whenInCollectionLinkWithPageTitleOnly_thenPageTitleShownOnFace() {
        let title = CardFace.faceTitle(
            type: .url,
            inCollection: true,
            isConcealed: false,
            customTitle: nil,
            ogTitle: "  SwiftUI Overview  "
        )
        #expect(title == "SwiftUI Overview")
        #expect(!CardFace.showsCustomTitleOnFace(inCollection: true, isConcealed: false, customTitle: nil))
    }

    @Test("in a collection, a non-link clip ignores any page title and whitespace custom title gives nil")
    func whenInCollectionNonLinkOrBlankTitle_thenNil() {
        #expect(CardFace.faceTitle(
            type: .text, inCollection: true, isConcealed: false, customTitle: "   ", ogTitle: "Ignored"
        ) == nil)
        #expect(!CardFace.showsCustomTitleOnFace(inCollection: true, isConcealed: false, customTitle: "   "))
    }

    @Test("a concealed clip hides its title even inside a collection")
    func whenConcealedInCollection_thenNoFaceTitle() {
        #expect(CardFace.faceTitle(
            type: .url, inCollection: true, isConcealed: true, customTitle: "Secret", ogTitle: "Hidden"
        ) == nil)
        #expect(!CardFace.showsCustomTitleOnFace(inCollection: true, isConcealed: true, customTitle: "Secret"))
    }

    @Test("a card title reduces the body height budget while keeping at least one line")
    func whenCardHasFaceTitle_thenBodyHeightAccountsForTitle() {
        let metrics = PestoMobile.CardMetrics(width: 179, typeSize: .large)
        #expect(metrics.bodyHeight(hasTitle: true) < metrics.bodyHeight(hasTitle: false))
        #expect(metrics.lines(.callout, hasTitle: true) <= metrics.lines(.callout, hasTitle: false))

        let huge = PestoMobile.CardMetrics(width: 179, typeSize: .accessibility5)
        #expect(huge.bodyHeight(hasTitle: true) >= 0)
        #expect(huge.lines(.callout, hasTitle: true) >= 1)
    }

    @MainActor
    private func renderFace(_ item: ClipboardItem, face: PestoMobile.CardFace, media: CardMediaState, inCollection: Bool) -> Data {
        let cardSize = CGSize(width: 179, height: CardGridLayout.cardHeight(forWidth: 179))
        let view = ClipCardFace(
            item: item,
            face: face,
            media: media,
            width: cardSize.width,
            revision: ClipCard.Revision(item),
            inCollection: inCollection
        )
        .frame(width: cardSize.width, height: cardSize.height)
        .background(Color.white)
        .environment(\.pestoSurface, .white)
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = .light
        host.view.bounds = CGRect(origin: .zero, size: cardSize)
        host.view.layoutIfNeeded()
        return UIGraphicsImageRenderer(size: cardSize).pngData { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
    }

    @Test("rendering ClipCardFace in a collection draws titles across text, links, pictures, and colors")
    @MainActor
    func whenClipCardFaceRenderedInCollection_thenTitleAppearsAcrossAllKinds() throws {
        let container = try ModelContainerSetup.makeInMemory()
        let context = ModelContext(container)

        let textItem = ClipboardItem(
            type: .text, sourceAppName: "Notes", previewText: "Body line one\nBody line two",
            contentHash: "h1", byteSize: 27, deviceID: "d", sequenceNumber: 1
        )
        textItem.customTitle = "Release notes"
        context.insert(textItem)
        #expect(
            renderFace(textItem, face: .text, media: CardMediaState(), inCollection: false)
                != renderFace(textItem, face: .text, media: CardMediaState(), inCollection: true)
        )

        let linkItem = ClipboardItem(
            type: .url, sourceAppName: "Safari", previewText: "https://developer.apple.com/documentation/swiftui",
            contentHash: "h2", byteSize: 50, deviceID: "d", sequenceNumber: 2
        )
        linkItem.ogTitle = "SwiftUI Documentation"
        context.insert(linkItem)
        let linkFace = PestoMobile.CardFace.decide(.init(
            type: .url, text: linkItem.previewText, isConcealed: false, hasLinkPicture: false
        ))
        #expect(
            renderFace(linkItem, face: linkFace, media: CardMediaState(), inCollection: false)
                != renderFace(linkItem, face: linkFace, media: CardMediaState(), inCollection: true)
        )

        let samplePicture = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 160)).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 240, height: 160))
        }
        let linkMedia = CardMediaState(linkPicture: samplePicture)
        #expect(
            renderFace(linkItem, face: .linkPicture, media: linkMedia, inCollection: false)
                != renderFace(linkItem, face: .linkPicture, media: linkMedia, inCollection: true)
        )

        let colorItem = ClipboardItem(
            type: .color, sourceAppName: "Photos", previewText: "#2F7A49",
            contentHash: "h3", byteSize: 7, deviceID: "d", sequenceNumber: 3
        )
        colorItem.customTitle = "Basil accent"
        context.insert(colorItem)
        let colorFace = PestoMobile.CardFace.decide(.init(type: .color, text: "#2F7A49", isConcealed: false))
        #expect(
            renderFace(colorItem, face: colorFace, media: CardMediaState(), inCollection: false)
                != renderFace(colorItem, face: colorFace, media: CardMediaState(), inCollection: true)
        )
    }
}
