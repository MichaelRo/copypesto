// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("Which copy actions a clip's menus offer")
@MainActor
struct CardCopyActionsTests {
    private func facts(
        _ type: ClipboardType, secret: Bool = false, covered: Bool = false, filtered: Bool = false,
        pending: Bool = false, color: Bool = false, recognized: Bool = false
    ) -> CardCopyActions.Facts {
        .init(
            type: type, isSecret: secret, isCovered: covered, isFiltered: filtered, isPending: pending,
            hasColor: color, offersRecognizedText: recognized
        )
    }

    @Test("text, code and links offer the Mac's transforms for their kind")
    func whenTextLike_thenTheMacsTransforms() {
        #expect(CardCopyActions.offer(for: facts(.text)).transforms == TextTransform.available(for: .text))
        #expect(CardCopyActions.offer(for: facts(.url)).transforms.contains(.removeTrackingParams))
        #expect(CardCopyActions.offer(for: facts(.code)).transforms.contains(.markdownCodeBlock))
        #expect(CardCopyActions.offer(for: facts(.text)).transforms.contains(.stripFormatting))
    }

    @Test("a color offers its formats, only when a color can be read from it")
    func whenColor_thenFormats() {
        #expect(CardCopyActions.offer(for: facts(.color, color: true)).colorFormats == ColorCopyFormat.allCases)
        #expect(CardCopyActions.offer(for: facts(.color)).isEmpty)
    }

    @Test("a picture offers Save to Photos, and Copy Recognized Text only when it read some text")
    func whenPicture_thenSaveAndMaybeRecognizedText() {
        let plain = CardCopyActions.offer(for: facts(.image))
        #expect(plain.offersSaveToPhotos)
        #expect(!plain.offersRecognizedText)
        #expect(CardCopyActions.offer(for: facts(.image, recognized: true)).offersRecognizedText)
    }

    @Test("a secret, a covered, a filtered or a pending clip and a file offer nothing")
    func whenHiddenOrUnjudged_thenNothing() {
        for type in ClipboardType.allCases {
            #expect(CardCopyActions.offer(for: facts(type, secret: true, color: true, recognized: true)).isEmpty)
            #expect(CardCopyActions.offer(for: facts(type, covered: true, color: true, recognized: true)).isEmpty)
            #expect(CardCopyActions.offer(for: facts(type, filtered: true, color: true, recognized: true)).isEmpty)
            #expect(CardCopyActions.offer(for: facts(type, pending: true, color: true, recognized: true)).isEmpty)
        }
        #expect(CardCopyActions.offer(for: facts(.file)).isEmpty)
    }

    @Test("Copy As writes the transformed text and moves the clip to the front; a color copies in the chosen format")
    func whenCopiedAs_thenTheTransformedTextIsOnTheClipboard() async throws {
        let library = try await MobileTestLibrary()
        let note = try await library.add("hello world")
        let color = try await library.add("#FF8800")
        _ = try await library.add("something newer")

        #expect(library.state.copyTransformed(note, by: .uppercase))
        #expect(AppPasteboard.general.string == "HELLO WORLD")
        #expect(library.state.copyColor(color, as: .rgb))
        #expect(AppPasteboard.general.string?.hasPrefix("rgb") == true)
        try await library.refreshed()
        #expect(library.store.items.first?.id == color.id)
    }

    @Test("a transform a clip does not offer is refused")
    func whenNotOffered_thenRefused() async throws {
        let library = try await MobileTestLibrary()
        let color = try await library.add("#FF8800")
        AppPasteboard.general.string = "unchanged"

        #expect(!library.state.copyTransformed(color, by: .sha256Hash))
        #expect(AppPasteboard.general.string == "unchanged")
    }
}
