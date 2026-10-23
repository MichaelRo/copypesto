// SPDX-License-Identifier: MIT
import SwiftUI

/// The popover under an empty, focused search field: the last searches, newest first.
struct RecentSearchesList: View {
    let queries: [String]
    let onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent searches")
                .font(.caption)
                .pestoQuiet()
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            Divider()
            ForEach(queries, id: \.self) { query in
                Button {
                    onPick(query)
                } label: {
                    HStack {
                        Image(systemName: "clock")
                            .pestoQuiet()
                            .font(.caption)
                        Text(query)
                            .font(.subheadline)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .frame(width: 220)
    }
}
