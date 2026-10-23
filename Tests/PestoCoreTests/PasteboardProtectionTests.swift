// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Pasteboard protection")
struct PasteboardProtectionTests {
    @Test("every concealed marker counts as protected")
    func whenAnyConcealedMarker_thenProtected() {
        for marker in ExclusionRules.concealedTypeMarkers {
            #expect(PasteboardProtection.isProtected(types: ["public.utf8-plain-text", marker]), "\(marker)")
        }
    }

    @Test("ordinary types are not protected")
    func whenOrdinaryTypes_thenNotProtected() {
        #expect(!PasteboardProtection.isProtected(types: ["public.utf8-plain-text", "public.html"]))
        #expect(!PasteboardProtection.isProtected(types: []))
    }

    @Test("a stack entry carries whether it came from a protected clip")
    func stackItem_carriesProtection() {
        #expect(!PasteStack.Item(previewText: "a", payloadKind: .text("a")).isProtected)
        #expect(PasteStack.Item(previewText: "a", payloadKind: .text("a"), isProtected: true).isProtected)
    }
}
