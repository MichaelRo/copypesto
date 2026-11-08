// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import Testing
@testable import Pesto

@Suite("LinkOpener routes web addresses to the browser and file URLs to Finder")
struct LinkOpenerTests {
    @Test("https://example.com is titled Open in Browser and opens the URL in the browser")
    func whenWebURL_thenOpensInBrowser() {
        let action = LinkOpenPolicy.action(for: "https://example.com")
        var opened: [URL] = []
        var revealed: [[URL]] = []

        LinkOpener.perform(
            action,
            openURL: { opened.append($0) },
            revealInFinder: { revealed.append($0) }
        )

        #expect(LinkOpener.title(for: action) == "Open in Browser")
        #expect(LinkOpener.symbol(for: action) == "safari")
        #expect(opened.map(\.absoluteString) == ["https://example.com"])
        #expect(revealed.isEmpty)
    }

    @Test("file:///Applications/Safari.app is titled Show in Finder and reveals the file without launching it")
    func whenFileURL_thenRevealsInFinderWithoutLaunching() {
        let action = LinkOpenPolicy.action(for: "file:///Applications/Safari.app")
        var opened: [URL] = []
        var revealed: [[URL]] = []

        LinkOpener.perform(
            action,
            openURL: { opened.append($0) },
            revealInFinder: { revealed.append($0) }
        )

        #expect(LinkOpener.title(for: action) == "Show in Finder")
        #expect(LinkOpener.symbol(for: action) == "folder")
        #expect(opened.isEmpty, "a file URL must never be passed to NSWorkspace.open")
        #expect(revealed.first?.map(\.path) == ["/Applications/Safari.app"])
    }

    @Test("an unsupported scheme offers no title and performs neither action")
    func whenUnsupportedScheme_thenNoAction() {
        let action = LinkOpenPolicy.action(for: "javascript:alert(1)")
        var called = false

        LinkOpener.perform(
            action,
            openURL: { _ in called = true },
            revealInFinder: { _ in called = true }
        )

        #expect(LinkOpener.title(for: action) == nil)
        #expect(!called)
    }
}
