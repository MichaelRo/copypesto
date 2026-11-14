// SPDX-License-Identifier: MIT
import Foundation
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import PestoCore
@testable import PestoMobile

@Suite("Writing a clip to the clipboard")
@MainActor
struct MobileClipboardTests {
    @Test("a secret stays on this device and leaves the clipboard after two minutes")
    func whenProtected_thenLocalOnlyAndExpiring() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let options = MobileClipboard.options(protected: true, now: now)
        #expect(options[.localOnly] as? Bool == true)
        let expiry = try #require(options[.expirationDate] as? Date)
        #expect(expiry == now.addingTimeInterval(120))
    }

    @Test("an ordinary clip is written with no options, so Universal Clipboard can carry it")
    func whenNotProtected_thenNoOptions() {
        #expect(MobileClipboard.options(protected: false).isEmpty)
    }

    @Test("a link goes on the clipboard as a URL and as its text; a picture as its own bytes")
    func whenWritingKinds_thenEachHasItsTypes() throws {
        let url = try #require(URL(string: "https://copypesto.net"))
        let link = MobileClipboard.items(for: .link(url, text: "https://copypesto.net"))
        #expect(link.count == 1)
        #expect(link.first?[UTType.url.identifier] as? URL == url)
        #expect(link.first?[UTType.utf8PlainText.identifier] as? String == "https://copypesto.net")
        let png = Data([1, 2, 3])
        let picture = MobileClipboard.items(for: .picture(png, typeIdentifier: UTType.png.identifier))
        #expect(picture.first?[UTType.png.identifier] as? Data == png)
    }

    @Test("a write reaches the pasteboard it is given, which in a test is never the person's own")
    func whenWritten_thenThePasteboardHoldsTheText() throws {
        let board = try #require(UIPasteboard(name: UIPasteboard.Name("pesto-test-\(UUID().uuidString)"), create: true))
        defer { UIPasteboard.remove(withName: board.name) }

        MobileClipboard.write(.text("written words"), protected: false, to: board)

        #expect(board.string == "written words")
        #expect(AppPasteboard.general != UIPasteboard.general)
    }

    @Test("a clip's content opens from its type and payload: a link with an address is a link, else text")
    func whenContentIsMade_thenTheTypeDecides() throws {
        let url = try #require(URL(string: "https://apple.com"))
        #expect(ClipContent.make(type: .url, payload: Data("https://apple.com".utf8), mimeType: nil)
            == .link(url, text: "https://apple.com"))
        #expect(ClipContent.make(type: .url, payload: Data("not a link".utf8), mimeType: nil) == .text("not a link"))
        #expect(ClipContent.make(type: .image, payload: Data([1]), mimeType: "public.jpeg")
            == .picture(Data([1]), typeIdentifier: "public.jpeg"))
        #expect(ClipContent.make(type: .text, payload: Data(), mimeType: nil) == nil)
    }
}
