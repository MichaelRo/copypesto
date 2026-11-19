// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("Which AI actions a clip's menus offer")
struct CardAIActionsTests {
    private func facts(
        _ type: ClipboardType, secret: Bool = false, covered: Bool = false, filtered: Bool = false,
        pending: Bool = false, locked: Bool = false, availability: AIAvailability = .available, vision: Bool = true
    )
    -> CardAIActions.Facts {
        .init(
            type: type, isSecret: secret, isCovered: covered, isFiltered: filtered, isPending: pending,
            isLocked: locked, availability: availability, supportsVision: vision
        )
    }

    @Test("text and code offer the Mac's text actions and a picture offers Describe Image, all enabled")
    func whenTheModelIsReady_thenTheMacsActionsAreOffered() {
        for type in [ClipboardType.text, .code] {
            let offer = CardAIActions.offer(for: facts(type))
            #expect(offer.actions == AIAction.textActions)
            #expect(offer.isEnabled)
            #expect(offer.reason == nil)
        }
        #expect(CardAIActions.offer(for: facts(.image)).actions == [.describeImage])
        for type in [ClipboardType.url, .color, .file] {
            #expect(CardAIActions.offer(for: facts(type)).isEmpty)
        }
    }

    @Test("a secret, a covered, a filtered or a pending clip and a locked history offer nothing")
    func whenHiddenOrUnjudged_thenNothing() {
        for type in ClipboardType.allCases {
            #expect(CardAIActions.offer(for: facts(type, secret: true)).isEmpty)
            #expect(CardAIActions.offer(for: facts(type, covered: true)).isEmpty)
            #expect(CardAIActions.offer(for: facts(type, filtered: true)).isEmpty)
            #expect(CardAIActions.offer(for: facts(type, pending: true)).isEmpty)
            #expect(CardAIActions.offer(for: facts(type, locked: true)).isEmpty)
        }
    }

    @Test("a model that can never run here hides the actions; one that can be fixed or is off greys them out with why")
    func whenTheModelIsUnavailable_thenHiddenOrGreyedWithTheReason() {
        for reason in [AIAvailability.Reason.needsNewerMacOS, .deviceNotEligible] {
            #expect(CardAIActions.offer(for: facts(.text, availability: .unavailable(reason))).isEmpty)
        }
        for reason in [AIAvailability.Reason.notEnabled, .modelNotReady, .turnedOff, .unknown] {
            let offer = CardAIActions.offer(for: facts(.text, availability: .unavailable(reason)))
            #expect(offer.actions == AIAction.textActions)
            #expect(!offer.isEnabled)
            #expect(offer.reason == AIAvailability.unavailable(reason).message)
        }
    }

    @Test("Describe Image is greyed out, with its own reason, when the model cannot read pictures")
    func whenThereIsNoVision_thenDescribeImageSaysWhy() {
        let offer = CardAIActions.offer(for: facts(.image, vision: false))
        #expect(offer.actions == [.describeImage])
        #expect(!offer.isEnabled)
        #expect(offer.reason == CardAIActions.visionReason)
        #expect(CardAIActions.offer(for: facts(.text, vision: false)).isEnabled)
    }

    @Test("on this device the reasons speak of the device, not of a Mac")
    func whenTheReasonIsShown_thenItNamesThisDevice() {
        for reason in AIAvailability.Reason.allCases {
            let message = AIAvailability.unavailable(reason).message
            #expect(!message.contains("Mac"), "\(message)")
            #expect(!message.contains("macOS"), "\(message)")
        }
    }
}
