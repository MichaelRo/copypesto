// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Which list changes animate")
struct ListChangeMotionTests {
    private let ids = (0..<5).map { _ in UUID() }

    @Test("one clip added, removed, swapped or brought to the front animates")
    func whenOneClipChanges_thenAnimated() {
        #expect(ListChangeMotion.shouldAnimateChange(from: ids, to: [UUID()] + ids))
        #expect(ListChangeMotion.shouldAnimateChange(from: ids, to: Array(ids.dropFirst())))
        #expect(ListChangeMotion.shouldAnimateChange(from: ids, to: [ids[3]] + ids.filter { $0 != ids[3] }))
    }

    @Test("a rewrite of the whole list, or no change, does not")
    func whenTheListIsRewritten_thenNotAnimated() {
        #expect(!ListChangeMotion.shouldAnimateChange(from: ids, to: ids))
        #expect(!ListChangeMotion.shouldAnimateChange(from: ids, to: [ids[1]]))
        #expect(!ListChangeMotion.shouldAnimateChange(from: ids, to: ids.reversed()))
    }
}
