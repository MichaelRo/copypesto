// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The link a clip on the widget opens")
struct WidgetLinkTests {
    private let id = UUID()

    @Test("a built link reads back as its clip's id")
    func whenBuilt_thenItParsesBack() throws {
        let url = WidgetLink.url(for: id)

        #expect(url.absoluteString == "pesto://clip/\(id.uuidString)")
        #expect(WidgetLink.clipID(in: url) == id)
        #expect(try WidgetLink.clipID(in: #require(URL(string: "pesto://clip/\(id.uuidString.lowercased())"))) == id)
    }

    @Test(
        "anything else is not a widget link",
        arguments: [
            "https://clip/{id}", "pesto-other://clip/{id}", "pesto://open", "pesto://clip", "pesto://clip/",
            "pesto://clip/not-a-uuid", "pesto://clip/{id}/", "pesto://clip/{id}/extra", "pesto://clip//{id}",
            "pesto://paste/{id}", "pesto://clip/{id}?q=1", "pesto://clip/{id}#top", "pesto://user@clip/{id}",
            "pesto://clip:80/{id}", "pesto:clip/{id}", "pesto:///{id}", "pesto://clip/{id}x",
            "pesto://clip/%7B{id}%7D"
        ]
    )
    func whenTheShapeDiffers_thenItIsRefused(_ template: String) throws {
        let text = template.replacingOccurrences(of: "{id}", with: id.uuidString)
        let url = try #require(URL(string: text))

        #expect(WidgetLink.clipID(in: url) == nil, "\(text) was accepted")
    }

    @Test("a widget link is no automation request on the Mac")
    func whenTheMacReadsIt_thenItDoesNothing() {
        #expect(AutomationRequest(url: WidgetLink.url(for: id)) == nil)
    }
}
