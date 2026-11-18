// SPDX-License-Identifier: MIT
import Testing
import UIKit
@testable import PestoMobile

@Suite("Small decisions the views rely on: a picture's spoken label, a note's discard, cached line heights")
struct ReviewViewDecisionsTests {
    @Test("a picture says its kind, its size and the start of the text read in it")
    func whenLabelled_thenKindSizeAndText() {
        #expect(PictureLabel.make(width: 1200, height: 800, recognizedText: nil) == "Picture, 1,200 by 800")
        #expect(PictureLabel.make(width: nil, height: nil, recognizedText: "  ") == "Picture")
        #expect(
            PictureLabel.make(width: 10, height: 20, recognizedText: "Boarding pass")
                == "Picture, 10 by 20. Text in the picture: Boarding pass"
        )
    }

    @Test("a long recognized text is cut for speech")
    func whenTheTextIsLong_thenItIsCut() {
        let label = PictureLabel.make(width: 1, height: 1, recognizedText: String(repeating: "w", count: 500))

        #expect(label.hasSuffix(String(repeating: "w", count: PictureLabel.textLimit) + "\u{2026}"))
    }

    @Test("a note with anything typed asks before it is discarded; an empty one does not")
    func whenNoteHasText_thenDiscardAsks() {
        #expect(!NoteDraft.needsDiscardConfirmation(""))
        #expect(NoteDraft.needsDiscardConfirmation("a"))
        #expect(NoteDraft.needsDiscardConfirmation("  \n"))
    }

    @Test("a line height is the system's for that style and size, and is looked up once")
    func whenAskedTwice_thenTheSameAnswerFromTheCache() {
        let category = UIContentSizeCategory.accessibilityExtraLarge
        let expected = UIFont.preferredFont(
            forTextStyle: .caption1, compatibleWith: UITraitCollection(preferredContentSizeCategory: category)
        ).lineHeight

        let first = LineHeights.height(of: .caption1, in: category)
        let count = LineHeights.cachedCount
        let second = LineHeights.height(of: .caption1, in: category)

        #expect(first == expected && second == expected)
        #expect(LineHeights.cachedCount == count)
        #expect(LineHeights.height(of: .caption1, in: .small) < first)
    }
}
