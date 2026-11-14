// SPDX-License-Identifier: MIT
import Foundation
import Testing
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
}
