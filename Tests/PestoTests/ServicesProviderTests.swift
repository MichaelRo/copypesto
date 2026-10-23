// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import Testing
@testable import Pesto

@Suite("The Copy to Pesto service")
@MainActor
struct ServicesProviderTests {
    private func board() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("pesto-test-services-\(UUID().uuidString)"))
    }

    @Test("selected text is copied to the destination, plain, so the watcher records it")
    func whenTextIsSelected_thenItIsCopied() {
        let source = board()
        source.clearContents()
        source.setString("grandma's recipe", forType: .string)
        let destination = board()

        #expect(ServicesProvider.copyText(from: source, to: destination))
        #expect(destination.string(forType: .string) == "grandma's recipe")
        #expect(!PasteboardProtection.isProtected(types: (destination.types ?? []).map(\.rawValue)))
    }

    @Test("a service pasteboard with no text copies nothing and leaves the destination alone")
    func whenNoText_thenNothingIsCopied() {
        let source = board()
        let destination = board()
        destination.clearContents()
        destination.setString("keep me", forType: .string)

        #expect(!ServicesProvider.copyText(from: source, to: destination))
        #expect(destination.string(forType: .string) == "keep me")
    }
}
