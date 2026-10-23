// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Shelf key reference")
struct ShelfKeyReferenceTests {
    @Test("each key is listed once, with something to press and something it does")
    func whenListed_thenEveryEntryIsDistinctAndComplete() {
        let entries = ShelfKeyReference.entries

        #expect(Set(entries.map(\.action)).count == entries.count)
        #expect(entries.allSatisfy { !$0.keys.isEmpty && !$0.action.isEmpty })
        let codes = entries
            .flatMap { entry in
                entry.keyCodes
                    .map {
                        "\($0)-\(entry.needsCommand)-\(entry.needsShift)-\(entry.needsOption)-\(entry.requiresSearch)"
                    }
            }
        #expect(Set(codes).count == codes.count, "a key is listed under two actions")
    }

    @Test("actions read as sentence case, without a final full stop")
    func whenListed_thenActionsFollowTheCopyGuide() {
        for entry in ShelfKeyReference.entries {
            #expect(entry.action.first?.isUppercase == true, "\(entry.action)")
            #expect(!entry.action.hasSuffix("."), "\(entry.action)")
        }
    }

    @Test("the copy key is listed")
    func whenListed_thenCopyIsThere() {
        #expect(ShelfKeyReference.entries.contains { $0.keys == ["⌘", "C"] && $0.keyCodes == [8] })
    }
}
