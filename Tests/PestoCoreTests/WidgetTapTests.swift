// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("What a tap on a widget tile does")
struct WidgetTapTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func clip(_ kind: ClipboardType, whole: String? = nil) -> WidgetClip {
        WidgetClip(id: UUID(), kind: kind, text: "preview", fullText: whole, date: now)
    }

    @Test("Copy copies in place when the snapshot holds the whole text and in-place copy works; otherwise Pesto copies")
    func whenCopy_thenInPlaceOnlyWithTheWholeText() {
        let short = clip(.text, whole: "the whole text")
        let long = clip(.text)
        let picture = clip(.image)

        #expect(WidgetTap.decide(for: short, action: .copy, copiesInPlace: true) == .copyInPlace(short.id))
        #expect(WidgetTap
            .decide(for: short, action: .copy, copiesInPlace: false) == .link(WidgetLink.url(for: short.id)))
        #expect(WidgetTap.decide(for: long, action: .copy, copiesInPlace: true) == .link(WidgetLink.url(for: long.id)))
        #expect(
            WidgetTap.decide(for: picture, action: .copy, copiesInPlace: true) == .link(WidgetLink.url(for: picture.id))
        )
    }

    @Test("Open in Pesto shows every kind; Open the Clip opens a link in the browser and shows anything else")
    func whenOpening_thenTheLinkFollowsTheKind() {
        for kind in ClipboardType.allCases {
            let item = clip(kind, whole: "https://copypesto.net")
            #expect(
                WidgetTap.decide(for: item, action: .openInPesto, copiesInPlace: true)
                    == .link(WidgetLink.url(for: item.id, action: .show))
            )
            let opened = WidgetTap.decide(for: item, action: .openClip, copiesInPlace: true)
            #expect(opened == .link(WidgetLink.url(for: item.id, action: kind == .url ? .open : .show)), "\(kind)")
        }
    }

    @Test(
        "only a whole http or https address with a host is opened",
        arguments: [
            ("https://copypesto.net/guide?x=1", true), ("http://example.com", true), ("  https://example.com\n", true),
            ("HTTPS://EXAMPLE.COM", true), ("javascript:alert(1)", false), ("file:///etc/passwd", false),
            ("pesto://clip/x", false), ("mailto:a@b.c", false), ("https://", false), ("copypesto.net", false),
            ("see https://example.com", false), ("https://user:pw@example.com", false), ("", false),
            ("tel:123", false), ("ftp://example.com", false)
        ]
    )
    func whenALinkIsOpened_thenOnlyTheWebIsAllowed(_ text: String, allowed: Bool) {
        #expect((WidgetTap.webURL(in: text) != nil) == allowed, "\(text)")
    }
}
