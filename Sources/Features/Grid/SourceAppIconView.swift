// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

/// Source-app icon shown in the card header.
/// `size` defaults to 16 pt (image/URL overlay rows); pass 22 for the standard-card header.
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
                    .resizable()
                    .frame(width: size, height: size)
                    .pestoQuiet()
            }
        }
        .help(appName ?? "Unknown app")
    }
}
