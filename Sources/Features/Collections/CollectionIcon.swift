// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// Renders a collection's icon whether it is an emoji or an SF Symbol name.
struct CollectionIcon: View {
    let symbolName: String

    var body: some View {
        if CollectionSymbol.isEmoji(symbolName) {
            Text(symbolName)
        } else {
            Image(systemName: symbolName)
        }
    }
}
