// SPDX-License-Identifier: MIT
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import PestoCore
@testable import PestoMobile

@Suite("A card dragged out of the grid")
@MainActor
struct ClipDragTests {
    @Test("text goes out as text and a link as a URL, each with the clip's id for Pesto alone")
    func whenDragged_thenOtherAppsGetTheContent() throws {
        let id = UUID()
        let text = ClipDrag.provider(for: .text("basil"), clipID: id)
        #expect(text.hasItemConformingToTypeIdentifier(UTType.plainText.identifier))
        #expect(text.registeredTypeIdentifiers.contains(ClipDrag.clipIDType.identifier))

        let url = try #require(URL(string: "https://copypesto.net/"))
        let link = ClipDrag.provider(for: .link(url, text: url.absoluteString), clipID: id)
        #expect(link.hasItemConformingToTypeIdentifier(UTType.url.identifier))

        let png = ClipContent.picture(Data([1, 2, 3]), typeIdentifier: UTType.png.identifier)
        let picture = ClipDrag.provider(for: png, clipID: id)
        #expect(picture.hasItemConformingToTypeIdentifier(UTType.png.identifier))
    }

    @Test("a drop reads the clip's id back, and a drop from elsewhere has none")
    func whenDropped_thenTheIdComesBack() async {
        let id = UUID()
        let own = ClipDrag.provider(for: .text("basil"), clipID: id)
        #expect(await ClipDrag.clipID(in: [own]) == id)

        let foreign = NSItemProvider(object: "from another app" as NSString)
        #expect(await ClipDrag.clipID(in: [foreign]) == nil)
        #expect(!ClipDrag.isOwnDrag([foreign]))
        #expect(ClipDrag.isOwnDrag([own]))
    }
}
