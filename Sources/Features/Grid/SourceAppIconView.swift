// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

/// The source app's icon in a card's line of facts; an app macOS cannot find shows a quiet clipboard glyph, drawn at
/// its own proportions.
struct SourceAppIconView: View {
    let bundleID: String?
    let appName: String?
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let nsImage = SourceIconCache.shared.image(forBundleID: bundleID) {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size, height: size)
            } else {
                Image(systemName: "doc.on.clipboard")
                    .font(.caption)
                    .frame(width: size, height: size)
                    .pestoQuiet()
            }
        }
        .help(appName ?? SourceAppRecord.unknownDisplayName)
    }
}
