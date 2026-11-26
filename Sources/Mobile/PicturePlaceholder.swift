// SPDX-License-Identifier: MIT
import SwiftUI

/// What a picture card shows before its picture is drawn: while it loads, and while it waits for its verdict (ADR
/// 0079). The same quiet ground and glyph as the Mac's card, so a picture appears with no "checking" step between.
struct PicturePlaceholder: View {
    var body: some View {
        Color.secondary.opacity(0.10)
            .overlay {
                Image(systemName: "photo")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tertiary)
            }
            .accessibilityHidden(true)
    }
}
