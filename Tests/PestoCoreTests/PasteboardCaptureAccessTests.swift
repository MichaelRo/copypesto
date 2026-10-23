// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("PasteboardCaptureAccess")
struct PasteboardCaptureAccessTests {
    @Test("always-allow is healthy and needs no warning")
    func whenAlwaysAllow_thenAllowed() {
        let access = PasteboardCaptureAccess(behaviorRawValue: 2)

        #expect(access == .allowed)
        #expect(access.needsAttention == false)
    }

    @Test("always-deny means capture is blocked and needs attention")
    func whenAlwaysDeny_thenBlocked() {
        let access = PasteboardCaptureAccess(behaviorRawValue: 3)

        #expect(access == .blocked)
        #expect(access.needsAttention)
    }

    @Test("ask means every capture may prompt, which needs attention")
    func whenAsk_thenPrompting() {
        let access = PasteboardCaptureAccess(behaviorRawValue: 1)

        #expect(access == .prompting)
        #expect(access.needsAttention)
    }

    @Test("default means no prompt has happened yet and is not flagged")
    func whenDefault_thenNotDecidedAndQuiet() {
        let access = PasteboardCaptureAccess(behaviorRawValue: 0)

        #expect(access == .notDecided)
        #expect(access.needsAttention == false)
    }

    @Test("onboarding explains macOS's pasteboard alert only where it can still appear")
    func whenNotAllowedYet_thenTheAlertMayAppear() {
        #expect(PasteboardCaptureAccess(behaviorRawValue: 0).asksOrWillAsk, "no choice made yet")
        #expect(PasteboardCaptureAccess(behaviorRawValue: 1).asksOrWillAsk, "ask every time")
        #expect(!PasteboardCaptureAccess(behaviorRawValue: 2).asksOrWillAsk, "always allow")
        #expect(!PasteboardCaptureAccess(behaviorRawValue: 3).asksOrWillAsk, "denied: the alert will not appear")
    }

    @Test("an unknown raw value is treated as allowed rather than raising a false alarm")
    func whenUnknown_thenAllowed() {
        #expect(PasteboardCaptureAccess(behaviorRawValue: 99) == .allowed)
    }

    @Test("a provider's value is mapped")
    func whenProviderSaysDeny_thenBlocked() {
        struct Deny: PasteboardAccessProviding {
            var behaviorRawValue: Int {
                3
            }
        }

        #expect(PasteboardCaptureAccess.current(from: Deny()) == .blocked)
    }
}
