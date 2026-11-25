// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The whole Clip window while clip contents are covered: nothing of the clip, and a way to close.
struct ClipInspectorCover: View {
    let close: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Label("Hidden while clip contents are covered", systemImage: "eye.slash")
                .pestoCaption()
            Button("Close", action: close)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier(AccessibilityID.textEditCancelButton)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
