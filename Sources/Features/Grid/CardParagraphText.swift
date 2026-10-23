// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The body of a text or code card: its paragraphs, with a dotted gap for each blank line, inside the card's text
/// budget.
struct CardParagraphText: View {
    let paragraphs: [String]
    let fontSize: CGFloat
    let design: Font.Design
    let budget: CGFloat

    var body: some View {
        ParagraphColumn(budget: budget) {
            ForEach(paragraphs.indices, id: \.self) { index in
                if index > 0 { ParagraphColumn.gap() }
                Text(paragraphs[index])
                    // Text size capped: fills a fixed-size card.
                        .scaledFont(size: fontSize, design: design, maxScale: 1.3)
                        .lineSpacing(2)
                        .foregroundStyle(.primary.opacity(0.92))
            }
        }
        // No `.clipped()`: on a Layout it renders the text white in a light appearance (`CardParagraphTextTests`). What
        // the layout leaves unplaced is outside the card, whose own clip shape cuts it.
    }
}
