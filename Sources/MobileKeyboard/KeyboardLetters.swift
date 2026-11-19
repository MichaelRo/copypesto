// SPDX-License-Identifier: MIT
import SwiftUI

/// The search page's keys (ADR 0063): lowercase letters or numbers and punctuation. They type into Pesto's own search
/// field and nowhere else: the only thing this view holds is the model, whose search methods change only the query,
/// and neither knows the app's text field (`KeyboardSearchTests` scans both).
struct KeyboardLetters: View {
    enum Layout {
        case letters
        case digits
    }

    let model: KeyboardModel
    let layout: Layout

    private var rows: [[String]] {
        switch layout {
        case .letters:
            [
                ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
                ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
                ["z", "x", "c", "v", "b", "n", "m"]
            ]
        case .digits:
            KeyboardPad.rows
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { key in
                        Button { model.typeInSearch(key) } label: {
                            Text(verbatim: key)
                                .font(.title3)
                                .minimumScaleFactor(0.6)
                                .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 40)
                        }
                        .buttonStyle(KeyboardKeyStyle())
                    }
                }
                .padding(.horizontal, CGFloat(10 - row.count) * 16)
            }
        }
    }
}
