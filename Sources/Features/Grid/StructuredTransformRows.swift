// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The JSON and Markdown rows at the top of Paste As and Copy As. What a clip qualifies for is worked out here, when
/// the menu opens, because it reads the clip (a spreadsheet copy is parsed, a table is converted) and a card update
/// must not pay for that.
struct StructuredTransformRows: View {
    let item: ClipboardItem
    let offered: ((ClipboardItem) -> [TextTransform])?
    let perform: ((ClipboardItem, TextTransform) -> Void)?

    var body: some View {
        let entries = offered?(item) ?? []
        if !entries.isEmpty, let perform {
            ForEach(entries, id: \.self) { transform in
                Button {
                    perform(item, transform)
                } label: {
                    Label(transform.rawValue, systemImage: transform.symbolName)
                }
            }
            Divider()
        }
    }
}
