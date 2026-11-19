// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// A collection's icon as the Mac stores it: an SF Symbol name or an emoji (`CollectionSymbol.isEmoji`).
struct CollectionIcon: View {
    let symbol: String

    var body: some View {
        if CollectionSymbol.isEmoji(symbol) {
            Text(symbol)
        } else {
            Image(systemName: symbol)
        }
    }
}
