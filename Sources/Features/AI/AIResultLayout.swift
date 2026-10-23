// SPDX-License-Identifier: MIT
import AppKit

/// How tall the answer's area is. A `ScrollView` reports almost no height of its own, so the panel used to size itself
/// to
/// a few lines and cut a longer answer short; the height now comes from the text, up to a cap past which it scrolls.
enum AIResultLayout {
    static let panelWidth: CGFloat = 340
    /// The panel's side padding is 16 on each side, and the answer sits in its own 16 point padding inside that.
    static let textWidth: CGFloat = panelWidth - 32
    static let minimumHeight: CGFloat = 90
    static let maximumHeight: CGFloat = 340

    static let floorHeight: CGFloat = 220
    /// Tall enough that nothing in the panel is squeezed while its height is measured.
    static let maximumMeasuredHeight: CGFloat = 1000

    /// The tallest the panel may be: its own ceiling, or 60 percent of the display's visible height on a small display,
    /// and never under what the header, a line of answer and the buttons need.
    static func panelCap(visibleHeight: CGFloat, readsInParts: Bool) -> CGFloat {
        let ceiling: CGFloat = readsInParts ? 560 : 520
        return max(floorHeight, min(ceiling, (visibleHeight * 0.6).rounded()))
    }

    static func answerHeight(for text: String, width: CGFloat) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        let measured = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: 12.5), .paragraphStyle: paragraph]
        )
        // Room for the vertical padding, and a line to spare in case a larger text size wraps one more.
        return min(max(ceil(measured.height) + 36, minimumHeight), maximumHeight)
    }
}
