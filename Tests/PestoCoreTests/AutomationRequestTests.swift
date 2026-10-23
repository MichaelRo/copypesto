// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("pesto:// links as requests")
struct AutomationRequestTests {
    private let id = UUID()

    private func request(_ link: String) -> AutomationRequest? {
        URL(string: link).flatMap { AutomationRequest(url: $0) }
    }

    @Test("open and list take nothing")
    func whenOpenOrList_thenARequest() {
        #expect(request("pesto://open") == .open)
        #expect(request("pesto://list") == .list)
    }

    @Test("search carries its text, and is still a request without any")
    func whenSearch_thenTextIsOptional() {
        #expect(request("pesto://search?q=invoice") == .search("invoice"))
        #expect(request("pesto://search?q=two%20words") == .search("two words"))
        #expect(request("pesto://search") == .search(nil))
        #expect(request("pesto://search?q=") == .search(nil))
    }

    @Test("paste, pin and summary need a clip id", arguments: ["paste", "pin", "summary"])
    func whenAnIdActionHasNoValidId_thenNoRequest(action: String) {
        #expect(request("pesto://\(action)") == nil)
        #expect(request("pesto://\(action)?id=not-a-uuid") == nil)
        #expect(request("pesto://\(action)?id=\(id.uuidString)") != nil)
    }

    @Test("each id action keeps its own case")
    func whenIdActions_thenTheirOwnCases() {
        #expect(request("pesto://paste?id=\(id.uuidString)") == .paste(id))
        #expect(request("pesto://pin?id=\(id.uuidString)") == .pin(id))
        #expect(request("pesto://summary?id=\(id.uuidString)") == .summary(id))
    }

    @Test("a collection is named, and pinboard is its old spelling")
    func whenCollection_thenNeedsAName() {
        #expect(request("pesto://collection?name=Work") == .collection("Work"))
        #expect(request("pesto://pinboard?name=Work") == .collection("Work"))
        #expect(request("pesto://collection") == nil)
        #expect(request("pesto://collection?name=") == nil)
    }

    @Test("clear needs a known range, so a bare link on a web page wipes nothing")
    func whenClear_thenARangeIsRequired() {
        #expect(request("pesto://clear") == nil)
        #expect(request("pesto://clear?range=yesterday") == nil)
        #expect(request("pesto://clear?range=hour") == .clear(.lastHour))
        #expect(request("pesto://clear?range=today") == .clear(.today))
        #expect(request("pesto://clear?range=all") == .clear(.all))
    }

    @Test("another scheme or an unknown action is no request")
    func whenForeign_thenNoRequest() {
        #expect(request("https://open") == nil)
        #expect(request("pesto://delete-everything") == nil)
        #expect(request("pesto:///open") == nil)
    }
}
