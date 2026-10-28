// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// "Fill From Mac": the placeholders Pesto fills in by itself, as a menu, so the text box is not crowded with chips.
struct FillFromMacMenu: View {
    let insert: (String) -> Void

    var body: some View {
        PopUpMenuButton(items: SnippetDraft.placeholders.map { placeholder in
            .action("\(placeholder.token)  \(placeholder.meaning)") { insert(placeholder.token) }
        }) {
            Text("Fill From Mac\u{2026}")
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .fixedSize()
        .help("Put a date, the clipboard or the app's name in the text")
    }
}
