// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("AI availability")
struct AIAvailabilityTests {
    @Test("each reason the model can be missing has its own plain explanation")
    func whenUnavailable_thenEachReasonExplainsItself() {
        let messages = AIAvailability.Reason.allCases.map { AIAvailability.unavailable($0).message }
        #expect(Set(messages).count == AIAvailability.Reason.allCases.count)
        #expect(messages.allSatisfy { !$0.isEmpty })
        #expect(AIAvailability.available.message.isEmpty)
    }

    @Test("only .available is available")
    func whenChecked_thenOnlyAvailableIsAvailable() {
        #expect(AIAvailability.available.isAvailable)
        for reason in AIAvailability.Reason.allCases {
            #expect(!AIAvailability.unavailable(reason).isAvailable)
        }
    }

    @Test("the messages tell the user what to do, not what went wrong internally")
    func whenNotEnabled_thenPointsToSystemSettings() {
        #expect(AIAvailability.unavailable(.notEnabled).message.contains("System Settings"))
        #expect(AIAvailability.unavailable(.needsNewerMacOS).message.contains("macOS 26"))
    }

    @Test("Apple Intelligence is on until the person turns it off, and then nothing reports as available")
    func whenSwitchedOff_thenUnavailableWhateverTheMacSays() {
        let defaults = ThrowawayDefaults.make()

        #expect(AIAvailability.isUserEnabled(defaults: defaults))
        defaults.set(false, forKey: AIAvailability.enabledDefaultsKey)
        #expect(!AIAvailability.isUserEnabled(defaults: defaults))
        #expect(AIAvailability.current(defaults: defaults) == .unavailable(.turnedOff))
        #expect(AIAvailability.unavailable(.turnedOff).message.contains("settings"))

        defaults.set(true, forKey: AIAvailability.enabledDefaultsKey)
        #expect(AIAvailability.isUserEnabled(defaults: defaults))
        #expect(AIAvailability.current(defaults: defaults) == AIAvailability.system)
    }

    @Test("text actions need the model, and describing a picture also needs vision")
    func whenActionChecked_thenMatchesWhatItNeeds() {
        let ready = AIAvailability.available
        let missing = AIAvailability.unavailable(.notEnabled)
        #expect(AIAction.summarize.isEnabled(availability: ready, supportsVision: false))
        #expect(!AIAction.summarize.isEnabled(availability: missing, supportsVision: true))
        #expect(!AIAction.describeImage.isEnabled(availability: ready, supportsVision: false))
        #expect(AIAction.describeImage.isEnabled(availability: ready, supportsVision: true))
    }

    @Test("images always list Describe Image so it can be shown greyed out, links and files list nothing")
    func whenTypeChecked_thenActionsListed() {
        #expect(AIAction.actions(for: .image) == [.describeImage])
        #expect(AIAction.actions(for: .text) == AIAction.textActions)
        #expect(AIAction.actions(for: .code) == AIAction.textActions)
        #expect(AIAction.actions(for: .url).isEmpty)
    }

    @Test("this Mac's real answer is one of the two states")
    func whenCurrent_thenConsistent() {
        let current = AIAvailability.current
        #expect(current.isAvailable == (current.message.isEmpty))
    }

    @Test(
        "a Mac that can never run it hides the AI controls; one the person can fix shows them disabled with the reason"
    )
    func presentation_followsAdr0007() {
        #expect(AIAvailability.available.presentation == .enabled)
        #expect(AIAvailability.unavailable(.needsNewerMacOS).presentation == .hidden)
        #expect(AIAvailability.unavailable(.deviceNotEligible).presentation == .hidden)
        for reason in [AIAvailability.Reason.notEnabled, .modelNotReady, .unknown, .turnedOff] {
            let state = AIAvailability.unavailable(reason)
            #expect(state.presentation == .disabled(state.message), "\(reason)")
        }
    }

    @Test("only the reason that needs a System Settings change offers a button for it")
    func opensSystemSettings_onlyWhenNotEnabled() {
        for reason in AIAvailability.Reason.allCases {
            #expect(AIAvailability.unavailable(reason).canBeFixedInSystemSettings == (reason == .notEnabled))
        }
        #expect(!AIAvailability.available.canBeFixedInSystemSettings)
    }
}
