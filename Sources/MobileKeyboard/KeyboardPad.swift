// SPDX-License-Identifier: MIT
import SwiftUI

/// Numbers and punctuation the person types one at a time: real typed input that works without Full Access, which
/// Apple asks of every keyboard (App Store Review Guideline 4.4.1, ADR 0061), and handy beside a clip.
struct KeyboardPad: View {
    let insert: (String) -> Void

    static let rows: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
        [".", ",", "?", "!", "'", "#", "%", "*", "+", "="]
    ]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Self.rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { character in
                        Button { insert(character) } label: {
                            Text(verbatim: character)
                                .font(.title3)
                                .minimumScaleFactor(0.6)
                                .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 44)
                        }
                        .buttonStyle(KeyboardKeyStyle())
                    }
                }
            }
        }
    }
}
