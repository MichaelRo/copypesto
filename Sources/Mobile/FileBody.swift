// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

struct FileBody: View {
    let preview: String
    var hasTitle = false

    var body: some View {
        let files = FileClip.summary(of: preview)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.fill")
                .font(.title)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(files.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(hasTitle ? 2 : 3)
                if !files.subtitle.isEmpty {
                    Text(files.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}
