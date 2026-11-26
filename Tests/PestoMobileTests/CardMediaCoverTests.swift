// SPDX-License-Identifier: MIT
import Foundation
import Testing
import UIKit
@testable import PestoCore
@testable import PestoMobile

@Suite("A covered iPhone card holds no pixels of its picture (ADR 0077)")
@MainActor
struct CardMediaCoverTests {
    private func still() -> CardMedia.Picture {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            UIColor.systemRed.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        return CardMedia.Picture(image: image, isAnimated: false)
    }

    private func picture(pending: Bool) -> ClipboardItem {
        let item = ClipboardItem(
            type: .image, sourceAppName: "Photos", previewText: "", contentHash: UUID().uuidString,
            byteSize: 512, deviceID: "test-device", sequenceNumber: 1
        )
        item.analysisPending = pending
        return item
    }

    @Test("a covered card does not load its picture or its link picture")
    func whenCardIsCovered_thenItsPictureIsNotLoaded() async {
        let state = CardMediaState()
        var pictureLoads = 0
        var linkLoads = 0
        await state.load(
            for: .init(id: UUID(), isShown: false, byteSize: 512, isConcealed: true),
            picture: {
                pictureLoads += 1
                return still()
            },
            linkPreview: {
                linkLoads += 1
                return nil
            }
        )
        #expect(pictureLoads == 0 && linkLoads == 0)
        #expect(state.picture == nil)
    }

    @Test("when the cover lifts, the picture loads at the clip's current size")
    func whenCoverLifts_thenThePictureLoads() async {
        let state = CardMediaState()
        let id = UUID()
        await state.load(for: .init(id: id, isShown: false, byteSize: 512, isConcealed: true), picture: { still() })
        await state.load(for: .init(id: id, isShown: false, byteSize: 4096, isConcealed: false), picture: { still() })
        #expect(state.picture != nil)
    }

    @Test("a card that becomes covered lets go of the picture it held")
    func whenCardBecomesCovered_thenTheHeldPictureGoes() async {
        let state = CardMediaState(picture: still(), linkPicture: still().image)
        await state.load(picture(pending: true), container: nil, isShown: false, isConcealed: true)
        #expect(state.picture == nil)
        #expect(state.linkPicture == nil)
    }
}
