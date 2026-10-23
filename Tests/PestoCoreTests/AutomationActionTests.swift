// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("AutomationAction")
struct AutomationActionTests {
    @Test("every documented host maps to an action")
    func documentedHostsMap() {
        for host in ["open", "list", "search", "paste", "pin", "collection", "clear", "summary"] {
            #expect(AutomationAction(host: host) != nil, "\(host)")
        }
    }

    @Test("collection is the new name and pinboard its deprecated alias for the same action")
    func collectionAndPinboardAreTheSame() {
        #expect(AutomationAction(host: "collection") == .collection)
        #expect(AutomationAction(host: "pinboard") == .collection)
    }

    @Test("an unknown host does nothing")
    func unknownHostIsNil() {
        #expect(AutomationAction(host: "delete-everything") == nil)
        #expect(AutomationAction(host: nil) == nil)
    }
}
