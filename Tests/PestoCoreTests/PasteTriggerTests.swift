// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

/// The paste log label used to embed the first 40 characters of the clipboard item, and it was
/// logged .public at notice level, which the system persists. The label may only name the trigger and the item id.
@Suite("PasteTrigger log labels")
struct PasteTriggerTests {
    private let id = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301") ?? UUID()

    @Test("an item-based trigger is labelled with its name and the item id")
    func itemTriggers_carryOnlyTheItemID() {
        #expect(PasteTrigger.overlaySelect(itemID: id).logLabel == "overlay-select item=\(id.uuidString)")
        #expect(PasteTrigger.stackAdvance(position: 2).logLabel == "stack-advance position=2")
        #expect(PasteTrigger.scriptOrURLScheme(itemID: id).logLabel == "script-or-url-scheme item=\(id.uuidString)")
    }

    @Test("triggers without an item are plain names")
    func plainTriggers_areJustNames() {
        #expect(PasteTrigger.quickMenu.logLabel == "quick-menu")
        #expect(PasteTrigger.quickPasteLast.logLabel == "quick-paste-last")
        #expect(PasteTrigger.pastePlainText.logLabel == "paste-plain-text")
        #expect(PasteTrigger.aiResult.logLabel == "ai-result")
        #expect(PasteTrigger.pinnedHotkey(slot: 3).logLabel == "pinned-hotkey slot=3")
    }

    @Test("no label can contain anything but the trigger name, an id or a slot")
    func labels_neverContainFreeText() {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz-=0123456789ABCDEF ")
        let triggers: [PasteTrigger] = [
            .overlaySelect(itemID: id), .stackAdvance(position: 2), .scriptOrURLScheme(itemID: id),
            .quickMenu, .quickPasteLast, .pastePlainText, .aiResult, .pinnedHotkey(slot: 9)
        ]
        for trigger in triggers {
            #expect(trigger.logLabel.unicodeScalars.allSatisfy(allowed.contains), "\(trigger.logLabel)")
        }
    }
}
