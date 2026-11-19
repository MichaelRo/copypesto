// SPDX-License-Identifier: MIT
import SwiftUI

/// A compact info button that reveals an explanation popover, keeping settings rows crisp and single-line.
struct InfoPopoverButton: View {
    let title: LocalizedStringKey
    private let message: Text
    @State private var isOpen = false
    @Environment(\.pestoAccent) private var accent

    init(_ title: LocalizedStringKey, message: LocalizedStringKey) {
        self.title = title
        self.message = Text(message)
    }

    init(title: LocalizedStringKey, message: LocalizedStringKey) {
        self.title = title
        self.message = Text(message)
    }

    init(_ title: LocalizedStringKey, verbatimMessage: String) {
        self.title = title
        message = Text(verbatim: verbatimMessage)
    }

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(isOpen ? accent : Color.primary.opacity(0.7))
                .opacity(isOpen ? 1 : 0.72)
                .frame(minWidth: 24, minHeight: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(title)
        .popover(isPresented: $isOpen, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                message
                    .pestoCaption()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 300, alignment: .leading)
            .padding(14)
        }
    }
}
