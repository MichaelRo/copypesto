// SPDX-License-Identifier: MIT
import SwiftUI

/// The search page's letters (ADR 0063). They type into Pesto's own search field and nowhere else: this view is given
/// only what to do with a letter, and knows nothing of the app's text field (a test scans it for that).
struct KeyboardLetters: View {
    let type: (String) -> Void

    static let rows: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"]
    ]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Self.rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { letter in
                        Button { type(letter) } label: {
                            Text(verbatim: letter)
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
