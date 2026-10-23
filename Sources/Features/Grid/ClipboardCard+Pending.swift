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

    /// The cover on a clip the content filter flagged, with its Show button.
    var nsfwBlurOverlay: some View {
        ZStack {
            Rectangle()
                .adaptiveMaterialFill()
            VStack(spacing: 6) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 20, weight: .medium))
                    .pestoQuiet()
                Text("Sensitive content")
                    // Text size capped: this overlay fills a fixed-size card.
                        .scaledFont(size: 10, weight: .semibold, maxScale: 1.3)
                        .pestoQuiet()
                Button {
                    reveal()
                } label: {
                    Text("Show")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pestoLink)
                .font(.caption2)
                .help("Show this clip. Return or a click pastes it without showing it.")
            }
        }
        .animation(Motion.animation(.easeInOut(duration: 0.15)), value: isNSFWRevealed)
    }
}
