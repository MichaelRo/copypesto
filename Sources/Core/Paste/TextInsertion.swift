// SPDX-License-Identifier: MIT
import ApplicationServices
import Foundation

protocol AXTextTarget: Sendable {
    func selectedRange() -> CFRange?
    func characterCount() -> Int?
    func setSelectedText(_ text: String) -> Bool
    func setSelectedRange(_ range: CFRange)
}

/// Tier 1 insertion. Many apps answer `.success` to a selected-text write and then ignore it, and a
/// Tier 2 fallback after a write that did land would paste twice, so success is judged from what changed.
enum TextInsertion {
    static func insert(_ text: String, into target: some AXTextTarget, caretOffsetFromEnd: Int? = nil) -> Bool {
        guard let range = target.selectedRange() else { return false }
        let countBefore = target.characterCount()
        guard target.setSelectedText(text) else { return false }

        let length = (text as NSString).length
        let expectedDelta = length - range.length
        let selectionUnchanged = target.selectedRange()
            .map { $0.location == range.location && $0.length == range.length }
            ?? false
        if let countBefore, let countAfter = target.characterCount() {
            if expectedDelta != 0 {
                if countAfter == countBefore { return false }
            } else if range.length > 0, selectionUnchanged {
                // Same length in and out: the count cannot tell, but a write that landed collapses the selection.
                return false
            }
        } else if selectionUnchanged {
            return false
        }
        let targetLocation: Int
        if let offset = caretOffsetFromEnd, offset > 0 {
            let splitIndex = text.index(text.endIndex, offsetBy: -offset, limitedBy: text.startIndex) ?? text.startIndex
            let prefixUTF16 = text[..<splitIndex].utf16.count
            targetLocation = range.location + prefixUTF16
        } else {
            targetLocation = range.location + length
        }
        target.setSelectedRange(CFRange(location: targetLocation, length: 0))
        return true
    }
}
