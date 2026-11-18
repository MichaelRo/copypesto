// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("The detail opens a clip off the main actor and lays out only the beginning of a very long text")
@MainActor
struct ClipDetailLoadingTests {
    @Test("a text up to the limit is shown whole")
    func whenShort_thenWhole() {
        let text = String(repeating: "a", count: DetailText.characterLimit)

        let detail = DetailText.make(text)

        #expect(detail.shown == text)
        #expect(!detail.isTruncated)
    }

    @Test("a text over the limit shows its first characters and says it is cut")
    func whenOverTheLimit_thenTheBeginningOnly() {
        let text = String(repeating: "b", count: DetailText.characterLimit + 1)

        let detail = DetailText.make(text)

        #expect(detail.shown.count == DetailText.characterLimit)
        #expect(detail.isTruncated)
    }

    @Test("many bytes in few characters is not cut, and a cut never splits a character")
    func whenMultibyte_thenCountedInCharacters() {
        let wide = String(repeating: "\u{1F600}", count: 6000)
        #expect(wide.utf8.count > DetailText.characterLimit)
        #expect(!DetailText.make(wide).isTruncated)

        let family = String(repeating: "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}", count: 30000)
        let detail = DetailText.make(family)
        #expect(detail.isTruncated)
        #expect(detail.shown.count == DetailText.characterLimit)
    }

    @Test("the clip opens from its id on a context of its own, as text, a link or a picture")
    func whenLoaded_thenTheContentIsOpened() async throws {
        let library = try await MobileTestLibrary()
        let note = try await library.add("opened off the main actor")
        let container = try #require(library.state.historyContainer)

        let content = await ClipContent.load(itemID: note.id, container: container)

        #expect(content == .text("opened off the main actor"))
        #expect(await ClipContent.load(itemID: UUID(), container: container) == nil)
        let payload = await ClipContent.payload(itemID: note.id, container: container)
        #expect(payload.flatMap { String(data: $0, encoding: .utf8) } == "opened off the main actor")
    }
}
