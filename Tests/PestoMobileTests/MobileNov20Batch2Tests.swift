// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
import UIKit
@testable import PestoCore
@testable import PestoMobile

@Suite("Batch 2: GIF upgrades, animated link previews, and selection snippets on iOS")
@MainActor
struct MobileBatch2Tests {
    private func solidUIImage(color: UIColor = .systemGreen) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }
    }

    @Test("CardMediaState key changes when byteSize increases after Chrome GIF upgrade or when concealed changes")
    func whenByteSizeChanges_thenMediaReloadKeyChanges() {
        let id = UUID()
        let before = CardMediaState.Key(id: id, isShown: true, byteSize: 400)
        let after = CardMediaState.Key(id: id, isShown: true, byteSize: 4096)
        let concealed = CardMediaState.Key(
            id: id, isShown: true, byteSize: 4096, isConcealed: true
        )

        #expect(before != after)
        #expect(after != concealed)
    }

    @Test("CardMediaState reloads when byteSize changes even if a static picture is already held")
    func whenStillUpgradesToAnimated_thenStateReloadsPicture() async {
        let id = UUID()
        let still = CardMedia.Picture(image: solidUIImage(), isAnimated: false)
        let animated = CardMedia.Picture(image: solidUIImage(), isAnimated: true)
        let state = CardMediaState()
        var calls = 0

        await state.load(
            for: CardMediaState.Key(id: id, isShown: true, byteSize: 100),
            picture: {
                calls += 1
                return still
            },
            linkPreview: { nil }
        )
        #expect(calls == 1)
        #expect(state.picture?.isAnimated == false)

        await state.load(
            for: CardMediaState.Key(id: id, isShown: true, byteSize: 2048),
            picture: {
                calls += 1
                return animated
            },
            linkPreview: { nil }
        )
        #expect(calls == 2)
        #expect(state.picture?.isAnimated == true)
    }

    @Test("CardMediaState animates GIF link previews when settled and clears on drop")
    func whenAnimatedLinkPreview_thenStateDecodesAndDropsFrames() async {
        let state = CardMediaState()
        let id = UUID()
        let still = solidUIImage()
        let frames = GIFFrames.Animation(frames: [still, solidUIImage(color: .systemBlue)], duration: 0.5)

        await state.load(
            for: CardMediaState.Key(id: id, isShown: true),
            picture: { nil },
            linkPreview: { (image: still, isAnimated: true) }
        )
        #expect(state.isLinkAnimated)
        await state.animate(
            settleDelay: .milliseconds(1),
            decode: { nil },
            linkDecode: { frames }
        )
        #expect(state.linkAnimation != nil)

        state.dropAnimation()
        #expect(state.linkAnimation == nil)
        #expect(state.isLinkAnimated)
        CardMedia.clearAnimationCache()
    }

    @Test("QuickInsert fillsWithoutAsking rejects selection so keyboard never expands it empty")
    func whenSelectionPlaceholder_thenQuickInsertSkipsIt() {
        #expect(!TemplateExpander.fillsWithoutAsking("Quote: {{selection}}"))
        #expect(TemplateExpander.fillsWithoutAsking("Today: {{isodate}}"))
    }

    @Test("SnippetFillRequest asks for both bare variables and selection on iOS and expands with selectedText")
    func whenSnippetHasBareVariableAndSelection_thenRequestAsksAndExpands() {
        let item = ClipboardItem(
            type: .text,
            previewText: "Hi {{name}}, {{selection}}",
            contentHash: "h",
            byteSize: 25,
            deviceID: "d",
            sequenceNumber: 1,
            isPinned: true
        )
        let outcome = SnippetFillRequest.make(
            for: item,
            text: "Hi {{name}}, {{selection}}",
            at: Date(timeIntervalSince1970: 1_800_000_000)
        )
        guard case let .ask(request) = outcome else {
            Issue.record("Expected ask outcome")
            return
        }
        #expect(request.plan.usesSelection)
        #expect(request.plan.fields.map(\.label) == ["name"])
        let expanded = request.expanded(
            fills: SnippetFills(values: ["name": "Maya"]),
            pastedClipboard: "",
            selectedText: "quoted line",
            at: Date(timeIntervalSince1970: 1_800_000_000)
        )
        #expect(expanded == "Hi Maya, quoted line")
    }
}
