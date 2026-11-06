// SPDX-License-Identifier: MIT
import CoreGraphics
import Testing
@testable import PestoCore

@Suite("Card treatment")
struct CardTreatmentTests {
    private func input(
        _ type: ClipboardType,
        text: String = "",
        concealed: Bool = false,
        picture: CardTreatmentInput.Picture? = nil,
        linkPictureShown: Bool = false,
        hasLinkMetadata: Bool = false,
        fill: HexColorComponents? = nil
    )
    -> CardTreatmentInput {
        CardTreatmentInput(
            type: type, text: text, isConcealed: concealed, picture: picture,
            linkPictureShown: linkPictureShown, hasLinkMetadata: hasLinkMetadata, colorFill: fill, backdropIsDark: true
        )
    }

    private let ordinary = CardTreatmentInput.Picture(aspectRatio: 1.5, isAnimated: false)

    // MARK: Pictures

    @Test("a picture that is loaded fills the card")
    func whenImageLoaded_thenFullBleed() {
        #expect(CardTreatment.decide(input(.image, picture: ordinary)) == .fullBleedPicture(.fill, isAnimated: false))
    }

    @Test("a GIF fills the card and says it is one")
    func whenGIF_thenAnimatedFullBleed() {
        let gif = CardTreatmentInput.Picture(aspectRatio: 1, isAnimated: true)
        #expect(CardTreatment.decide(input(.image, picture: gif)) == .fullBleedPicture(.fill, isAnimated: true))
    }

    @Test("a very tall screenshot is fitted, not cropped")
    func whenTallScreenshot_thenFit() {
        let tall = CardTreatmentInput.Picture(aspectRatio: 0.3, isAnimated: false)
        #expect(CardTreatment.decide(input(.image, picture: tall)) == .fullBleedPicture(.fit, isAnimated: false))
    }

    @Test("a picture still loading keeps the standard card, with its placeholder")
    func whenNoPictureYet_thenStandard() {
        #expect(CardTreatment.decide(input(.image)) == .standard)
    }

    @Test("a hidden, covered or masked picture keeps today's look")
    func whenImageConcealed_thenStandard() {
        #expect(CardTreatment.decide(input(.image, concealed: true, picture: ordinary)) == .standard)
    }

    // MARK: Colors

    @Test("a color fills the card with ink chosen for it")
    func whenColor_thenFullBleedColorWithInk() {
        let yellow = HexColorComponents(red: 1, green: 1, blue: 0)
        #expect(CardTreatment.decide(input(.color, text: "#FFFF00", fill: yellow)) == .fullBleedColor(.black))
        let navy = HexColorComponents(red: 0, green: 0, blue: 0.3)
        #expect(CardTreatment.decide(input(.color, text: "#00004D", fill: navy)) == .fullBleedColor(.white))
    }

    @Test("a color that cannot be read, or is covered, keeps the standard card")
    func whenColorUnreadableOrConcealed_thenStandard() {
        #expect(CardTreatment.decide(input(.color, text: "#zzz")) == .standard)
        let red = HexColorComponents(red: 1, green: 0, blue: 0)
        #expect(CardTreatment.decide(input(.color, text: "#F00", concealed: true, fill: red)) == .standard)
    }

    // MARK: Short text

    @Test("short text is set larger by length", arguments: [
        ("Hi", 24.0), (String(repeating: "a", count: 16), 24.0),
        (String(repeating: "a", count: 17), 20.0), (String(repeating: "a", count: 32), 20.0),
        (String(repeating: "a", count: 33), 17.0), (String(repeating: "a", count: 48), 17.0)
    ])
    func whenShortText_thenLargeByBucket(text: String, points: Double) {
        #expect(CardTreatment.decide(input(.text, text: text)) == .largeText(points: points))
    }

    @Test("text over 48 characters, with a line break, or empty stays standard", arguments: [
        String(repeating: "a", count: 49), "one\ntwo", "   ", ""
    ])
    func whenNotShort_thenStandard(text: String) {
        #expect(CardTreatment.decide(input(.text, text: text)) == .standard)
    }

    @Test("a trailing line break does not make one line two")
    func whenTrailingNewline_thenStillShort() {
        #expect(CardTreatment.decide(input(.text, text: "hello\n")) == .largeText(points: 24))
    }

    @Test("a lone emoji keeps its own large layout")
    func whenSingleGlyph_thenStandard() {
        #expect(CardTreatment.decide(input(.text, text: "🙂")) == .standard)
    }

    @Test("code, and short text that is concealed, keep today's look")
    func whenCodeOrConcealed_thenStandard() {
        #expect(CardTreatment.decide(input(.code, text: "let a = 1")) == .standard)
        #expect(CardTreatment.decide(input(.text, text: "hunter2", concealed: true)) == .standard)
    }

    @Test("the line limit follows the card's height budget and never passes three", arguments: [
        (24.0, 104.0, 3), (24.0 * 0.85, 64.0, 2), (17.0, 104.0, 3), (24.0, 20.0, 1), (24.0, 0.0, 1)
    ])
    func whenBudget_thenLinesFit(points: Double, budget: Double, lines: Int) {
        #expect(CardTreatment.largeTextLineLimit(points: points, heightBudget: budget) == lines)
    }

    @Test("the limit fits the budget at every slider width for every size")
    func whenSliding_thenLargeTextFitsTheBudget() {
        for width in CardMetrics.sliderRange {
            let size = CardMetrics.dimensions(width: width)
            let budget = Double(CardLayout.textHeightBudget(for: size))
            for points in [24.0, 20.0, 17.0] {
                let scaled = Double(CardTextScale.size(CGFloat(points), cardWidth: size.width))
                let lines = CardTreatment.largeTextLineLimit(points: scaled, heightBudget: budget)
                #expect(lines == 1 || Double(lines) * scaled * CardTreatment.lineHeightFactor <= budget)
            }
        }
    }

    // MARK: Links

    @Test("a link with no picture leads with its real host")
    func whenLinkWithoutPicture_thenHostFirst() {
        let link = LinkDisplay(host: "example.com", rest: "/a")
        #expect(CardTreatment.decide(input(.url, text: "https://example.com/a")) == .hostFirstLink(link))
    }

    @Test("a link whose picture is shown keeps its picture body")
    func whenLinkPicture_thenStandard() {
        #expect(CardTreatment.decide(input(.url, text: "https://example.com", linkPictureShown: true)) == .standard)
    }

    @Test("a link with a title, site name or icon keeps its rich body")
    func whenLinkHasMetadata_thenStandard() {
        #expect(CardTreatment.decide(input(.url, text: "https://example.com/a", hasLinkMetadata: true)) == .standard)
    }

    @Test("a link with no host, or one that is concealed, stays standard")
    func whenLinkWithoutHostOrConcealed_thenStandard() {
        #expect(CardTreatment.decide(input(.url, text: "mailto:a@b.example")) == .standard)
        #expect(CardTreatment.decide(input(.url, text: "https://example.com", concealed: true)) == .standard)
    }

    // MARK: Unchanged kinds

    @Test("files keep the standard card")
    func whenFile_thenStandard() {
        #expect(CardTreatment.decide(input(.file, text: "/Users/me/a.pdf")) == .standard)
    }
}
