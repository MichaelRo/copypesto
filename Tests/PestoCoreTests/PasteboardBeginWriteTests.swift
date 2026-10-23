// SPDX-License-Identifier: MIT
import AppKit
import Testing
@testable import PestoCore

@Suite("PasteboardProtection.beginWrite")
@MainActor
struct PasteboardBeginWriteTests {
    private func board() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("pesto-core-test-protection-\(UUID().uuidString)"))
    }

    private func types(of board: NSPasteboard) -> [String] {
        (board.types ?? []).map(\.rawValue)
    }

    @Test("a protected write carries the concealed marker and an ordinary write does not")
    func whenWriting_thenMarkerFollowsTheRequest() {
        let protectedBoard = board()
        PasteboardProtection.beginWrite(on: protectedBoard, protected: true)
        protectedBoard.setString("hunter2", forType: .string)
        #expect(PasteboardProtection.isProtected(types: types(of: protectedBoard)))

        let plainBoard = board()
        PasteboardProtection.beginWrite(on: plainBoard, protected: false)
        plainBoard.setString("lunch at noon", forType: .string)
        #expect(!PasteboardProtection.isProtected(types: types(of: plainBoard)))
    }

    @Test("a concealed copy from the command line or a script is dropped by the watcher's own rules")
    func whenConcealedCopy_thenPestoWouldDropIt() {
        let pb = board()
        PasteboardProtection.beginWrite(on: pb, protected: true)
        pb.setString("secret", forType: .string)

        #expect(ExclusionRules.concealedTypeMarkers.contains { types(of: pb).contains($0) })
    }
}
