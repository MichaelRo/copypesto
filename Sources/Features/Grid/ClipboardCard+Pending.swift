// SPDX-License-Identifier: MIT
import SwiftUI

extension ClipboardCard {
    /// A clip saved before it was read and screened is covered by a solid card until the verdict (a second or less). It
    /// is
    /// opaque on purpose: what is under it might be what the verdict hides.
    var analysisPendingOverlay: some View {
        ZStack {
            Rectangle().fill(Color.opaqueSurface)
            VStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking")
                    .scaledFont(size: 10, weight: .semibold, maxScale: 1.3)
                    .pestoQuiet()
            }
        }
        .accessibilityHidden(true)
    }
}
