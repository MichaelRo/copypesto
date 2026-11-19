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
        pending: Bool = false, color: Bool = false, recognized: Bool = false, jwt: Bool = false,
        allowsDecode: Bool = true, canAuthenticate: Bool = true, structured: [TextTransform] = []
    )
    -> CardCopyActions.Facts {
        .init(
            type: type, isSecret: secret, isCovered: covered, isFiltered: filtered, isPending: pending,
            hasColor: color, offersRecognizedText: recognized, isJWT: jwt, allowsDecode: allowsDecode,
            canAuthenticate: canAuthenticate, structured: structured
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

    @Test("a hidden token offers Decode JWT and nothing else, and only when it may be read and asked for")
    func whenAHiddenToken_thenOnlyDecode() {
        let offer = CardCopyActions.offer(for: facts(.text, secret: true, covered: true, jwt: true))
        #expect(offer.offersDecodeJWT)
        #expect(offer.transforms.isEmpty && offer.structured.isEmpty && !offer.offersSaveToPhotos)
        #expect(!CardCopyActions.offer(for: facts(.text, secret: true, jwt: false)).offersDecodeJWT)
        #expect(!CardCopyActions.offer(for: facts(.text, secret: true, jwt: true, allowsDecode: false)).offersDecodeJWT)
        #expect(!CardCopyActions.offer(for: facts(.text, secret: true, jwt: true, canAuthenticate: false))
            .offersDecodeJWT)
        #expect(!CardCopyActions.offer(for: facts(.text, jwt: true)).offersDecodeJWT)
    }

    @Test("JSON and Markdown lead a text clip's Copy As only for a clip that qualifies")
    func whenStructured_thenTheyComeFirst() {
        let offer = CardCopyActions.offer(for: facts(.text, structured: [.json, .markdown]))
        #expect(offer.structured == [.json, .markdown])
        #expect(!offer.transforms.contains(.json))
        #expect(CardCopyActions.offer(for: facts(.text)).structured.isEmpty)
        #expect(CardCopyActions.offer(for: facts(.text, secret: true, structured: [.json])).structured.isEmpty)
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

    @Test("Copy As JSON turns a table into rows of objects and Copy As Markdown a page's HTML into Markdown")
    func whenCopiedAsStructured_thenTheConversionIsOnTheClipboard() async throws {
        let library = try await MobileTestLibrary()
        let table = try await library.add("name,qty\napple,3\npear,5")
        let json = try await library.add("{\"a\":1,\"b\":[2,3]}")

        #expect(library.state.copyOffer(for: table).structured.contains(.json))
        #expect(library.state.copyTransformed(table, by: .json))
        #expect(AppPasteboard.general.string?.contains("\"name\"") == true)
        #expect(AppPasteboard.general.string?.contains("\"apple\"") == true)
        #expect(library.state.copyTransformed(json, by: .json))
        #expect(AppPasteboard.general.string?.contains("\n") == true)
        #expect(!library.state.copyTransformed(json, by: .markdown))

        let page = try await library.add(
            "<!DOCTYPE html><html><body><table><tr><th>Name</th><th>N</th></tr>"
                + "<tr><td>Ana</td><td>1</td></tr></table></body></html>"
        )
        #expect(library.state.copyOffer(for: page).structured.contains(.markdown))
        #expect(library.state.copyTransformed(page, by: .markdown))
        #expect(AppPasteboard.general.string == "| Name | N |\n| --- | --- |\n| Ana | 1 |")
    }

    @Test("a token's Decode JWT asks first, reads header and payload, and Copy Payload closes it")
    func whenDecodingAToken_thenItAsksAndIsHeldInMemory() async throws {
        let library = try await MobileTestLibrary()
        library.state.isActivated = true
        let token = Self.token(#"{"sub":"42","name":"Ada"}"#)
        try await library.service.ingest(#require(ClipCapture.text(token)))
        let item = try await library.settle()
        #expect(item.sensitivity == .jwt)
        #expect(library.state.copyOffer(for: item).offersDecodeJWT)

        let result = try #require(await library.state.decodeJWT(item))
        guard case let .decoded(decoding) = result else {
            Issue.record("not decoded")
            return
        }
        #expect(decoding.payloadJSON.contains("\"Ada\""))
        #expect(library.state.decodedJWT == result)

        library.state.copyDecodedPayload(decoding)
        #expect(AppPasteboard.general.string == decoding.payloadJSON)
        #expect(library.state.decodedJWT == nil)
    }

    @Test("a refused authentication decodes nothing")
    func whenAuthenticationIsRefused_thenNothingIsDecoded() async throws {
        let reveal = SecretReveal(
            authenticator: StubUserAuthenticator(available: true, grants: false), grace: AuthenticationGrace(),
            coversWhileCaptured: false
        )
        let library = try await MobileTestLibrary(reveal: reveal)
        library.state.isActivated = true
        try await library.service.ingest(#require(ClipCapture.text(Self.token(#"{"sub":"42"}"#))))
        let item = try await library.settle()

        #expect(await library.state.decodeJWT(item) == nil)
        #expect(library.state.decodedJWT == nil)
    }

    private static func token(_ payload: String) -> String {
        func part(_ json: String) -> String {
            Data(json.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return "\(part(#"{"alg":"HS256","typ":"JWT"}"#)).\(part(payload)).c2lnbmF0dXJlLWJ5dGVz"
    }
}
