// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// What a copy from another device shows where an app's icon would be: the same size and corner as one, in the accent,
/// so the card header keeps its rhythm and the clip reads as "from your phone" without reading as a warning.
struct RemoteSourceTile: View {
    @Environment(\.pestoAccent) private var accent

    var body: some View {
        Image(systemName: "iphone")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(accent)
            .frame(width: CardLayout.appTileSize, height: CardLayout.appTileSize)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(accent.opacity(0.16)))
            .help("Copied on another device")
    }
}
