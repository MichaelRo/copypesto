// SPDX-License-Identifier: MIT
import SwiftUI

/// The spinner a sheet shows while it works. It fills a fixed height so the sheet does not collapse around it when
/// the content swaps in and out.
struct SheetWorkingIndicator: View {
    var body: some View {
        ProgressView("Working\u{2026}")
            .frame(maxWidth: .infinity, minHeight: 140)
            .padding(.vertical, 12)
    }
}
