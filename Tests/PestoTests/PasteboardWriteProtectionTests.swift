// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import Testing
@testable import Pesto

@Suite("Pasteboard writes keep a secret protected")
@MainActor
struct PasteboardWriteProtectionTests {
    private func board() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("pesto-test-protection-\(UUID().uuidString)"))
    }

    private func types(of board: NSPasteboard) -> [String] {
        (board.types ?? []).map(\.rawValue)
    }

    @Test("a protected write carries the concealed marker")
    func whenProtected_thenMarked() {
        let pb = board()
        AppState.beginWrite(on: pb, protected: true)
        pb.setString("hunter2", forType: .string)
        #expect(PasteboardProtection.isProtected(types: types(of: pb)))
    }

    @Test("an ordinary write carries no marker")
    func whenNotProtected_thenUnmarked() {
        let pb = board()
        AppState.beginWrite(on: pb, protected: false)
        pb.setString("lunch at noon", forType: .string)
        #expect(!PasteboardProtection.isProtected(types: types(of: pb)))
    }

    @Test("rewriting a protected board keeps it protected")
    func whenRewrittenFromProtectedBoard_thenStillProtected() {
        let pb = board()
        AppState.beginWrite(on: pb, protected: true)
        pb.setString("hunter2", forType: .string)
        let keep = AppState.isProtected(pb)

        AppState.beginWrite(on: pb, protected: keep)
        pb.setString("HUNTER2", forType: .string)

        #expect(PasteboardProtection.isProtected(types: types(of: pb)))
    }
}
