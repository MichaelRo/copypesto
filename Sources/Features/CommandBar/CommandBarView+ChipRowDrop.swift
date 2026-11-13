// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import UniformTypeIdentifiers

extension CommandBarView {
    /// The row's drop target (reordering past the last chip, the gaps) sits on a background layer of the row's
    /// frame: an `.onDrop` on the row itself gave its whole frame to the first chip's accessibility element, which
    /// then covered the inline collection field and the chips after it whenever no app chip followed them.
    var chipRowDropLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .onDrop(
                of: [UTType.text, UTType.data],
                delegate: ChipRowDropDelegate(
                    appState: appState, baseOrder: pinboards.map(\.id), frames: chipFrames,
                    frozenFrames: $chipFrozenFrames, liveOrder: $chipLiveOrder, insertionBar: $chipInsertionBar,
                    onCommit: { persistPinboardOrder($0, moved: appState.draggingPinboardID) }
                )
            )
            .accessibilityHidden(true)
    }
}
