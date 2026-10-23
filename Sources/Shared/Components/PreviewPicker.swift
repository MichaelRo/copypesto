// SPDX-License-Identifier: MIT
import SwiftUI

/// A row of tiles that each draw a small picture of their choice, like the appearance choice in System Settings.
/// Every tile is a real button: focusable from the keyboard, announced with its label and whether it is selected.
struct PreviewPicker<Value: Hashable, Preview: View>: View {
    @Environment(\.pestoAccent) private var accent
    @Environment(\.colorSchemeContrast) private var contrast
    let title: String
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    let identifier: (Value) -> String
    @ViewBuilder let preview: (Value) -> Preview

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(options, id: \.self) { option in
                tile(for: option)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func tile(for option: Value) -> some View {
        let isSelected = option == selection
        return Button {
            selection = option
        } label: {
            VStack(spacing: 8) {
                preview(option)
                    .frame(width: 112, height: 92)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                isSelected ? accent : Color.primary.opacity(0.10),
                                lineWidth: isSelected ? 2.5 : 1
                            )
                    )
                Text(label(option))
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : AdaptiveContrast.quiet(contrast))
            }
        }
        .buttonStyle(.plain)
        .animation(Motion.animation(.easeOut(duration: 0.15)), value: isSelected)
        .accessibilityElement(children: .ignore)
        .selectableTile(verbatim: "\(title): \(label(option))", isSelected: isSelected) { selection = option }
        .accessibilityIdentifier(identifier(option))
    }
}
