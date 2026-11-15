// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The links a clip on the widget opens")
struct WidgetLinkTests {
    private let id = UUID()

    @Test("each action's link reads back as its clip and action")
    func whenBuilt_thenItParsesBack() throws {
        #expect(WidgetLink.url(for: id).absoluteString == "pesto://clip/\(id.uuidString)")
        #expect(WidgetLink.url(for: id, action: .show).absoluteString == "pesto://clip/\(id.uuidString)/show")
        #expect(WidgetLink.url(for: id, action: .open).absoluteString == "pesto://clip/\(id.uuidString)/open")
        for action in WidgetLink.Action.allCases {
            #expect(WidgetLink.target(in: WidgetLink.url(for: id, action: action)) == .init(id: id, action: action))
        }
        #expect(WidgetLink.clipID(in: WidgetLink.url(for: id)) == id)
        #expect(WidgetLink.clipID(in: WidgetLink.url(for: id, action: .show)) == nil)
        let lowercased = try #require(URL(string: "pesto://clip/\(id.uuidString.lowercased())/show"))
        #expect(WidgetLink.target(in: lowercased) == .init(id: id, action: .show))
    }

    @Test(
        "anything else is not a widget link",
        arguments: [
            "https://clip/{id}", "pesto-other://clip/{id}", "pesto://open", "pesto://clip", "pesto://clip/",
            "pesto://clip/not-a-uuid", "pesto://clip/{id}/", "pesto://clip/{id}/extra", "pesto://clip//{id}",
            "pesto://paste/{id}", "pesto://clip/{id}?q=1", "pesto://clip/{id}#top", "pesto://user@clip/{id}",
            "pesto://clip:80/{id}", "pesto:clip/{id}", "pesto:///{id}", "pesto://clip/{id}x",
            "pesto://clip/%7B{id}%7D", "pesto://clip/{id}/copy", "pesto://clip/{id}/show/", "pesto://clip/{id}/SHOW",
            "pesto://clip/{id}/open?url=https://example.com", "pesto://clip/{id}/show/open", "pesto://clip/show/{id}"
        ]
    )
    func whenTheShapeDiffers_thenItIsRefused(_ template: String) throws {
        let text = template.replacingOccurrences(of: "{id}", with: id.uuidString)
        let url = try #require(URL(string: text))

        #expect(WidgetLink.target(in: url) == nil, "\(text) was accepted")
    }

    @Test("a widget link is no automation request on the Mac")
    func whenTheMacReadsIt_thenItDoesNothing() {
        for action in WidgetLink.Action.allCases {
            #expect(AutomationRequest(url: WidgetLink.url(for: id, action: action)) == nil)
        }
    }
}
