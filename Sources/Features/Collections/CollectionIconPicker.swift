// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// Grid of SF Symbols to pick a pinboard icon.
struct CollectionIconPicker: View {
    @Environment(\.pestoAccent) private var accent
    @Binding var selection: String

    private let symbols = CollectionSymbols.symbols

    var body: some View {
        LazyVGrid(columns: Array(repeating: .init(.fixed(32)), count: 8), spacing: 8) {
            ForEach(symbols, id: \.self) { symbol in
                Button { selection = symbol } label: {
                    Image(systemName: symbol)
                        .font(.title3)
                        .frame(width: 32, height: 32)
                        .background(
                            selection == symbol ? accent.opacity(0.2) : Color.clear,
                            in: .rect(cornerRadius: 6)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .selectableTile(verbatim: CollectionSymbols.name(for: symbol), isSelected: selection == symbol) {
                    selection = symbol
                }
            }
        }
        .padding(8)
    }
}
