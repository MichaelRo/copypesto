// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The collection colours as swatches, then one more that opens the system colour panel for any colour. Presets
/// report at once; the panel reports every colour while it is dragged, so a caller that saves should wait for it to
/// settle (`CollectionColorSaver`).
struct CollectionColorRow: View {
    @Environment(\.pestoAccent) private var accent
    @Binding var colorHex: String
    var diameter: CGFloat = 20
    var spacing: CGFloat = 6
    var onChoose: (String) -> Void = { _ in }
    @State private var showCustomPicker = false

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(CollectionPalette.colors, id: \.self) { hex in
                let choose = {
                    showCustomPicker = false
                    AccentColorPanel.shared.close()
                    colorHex = hex
                    onChoose(hex)
                }
                Button(action: choose) {
                    swatch(fill: Color(hex: hex) ?? accent, isSelected: CollectionPalette.isSame(colorHex, hex))
                }
                .buttonStyle(.plain)
                .selectableTile(
                    verbatim: CollectionPalette.name(forHex: hex),
                    isSelected: CollectionPalette.isSame(colorHex, hex),
                    perform: choose
                )
            }
            Button {
                showCustomPicker.toggle()
            } label: {
                otherSwatch
            }
            .buttonStyle(.plain)
            .selectableTile("Color: Other", isSelected: CollectionPalette.isCustom(colorHex)) {
                showCustomPicker.toggle()
            }
            .accessibilityIdentifier(AccessibilityID.collectionOtherColor)
            .popover(isPresented: $showCustomPicker, arrowEdge: .bottom) {
                InlineColorPickerPopover(
                    hex: $colorHex,
                    fallbackColor: Color(hex: colorHex) ?? accent,
                    onPick: onChoose
                )
            }
        }
        .onDisappear { AccentColorPanel.shared.close() }
    }

    private func swatch(fill: Color, isSelected: Bool) -> some View {
        Circle()
            .fill(fill)
            .frame(width: diameter, height: diameter)
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(.white)
                }
            }
    }

    @ViewBuilder
    private var otherSwatch: some View {
        if CollectionPalette.isCustom(colorHex) {
            swatch(fill: Color(hex: colorHex) ?? accent, isSelected: true)
        } else {
            Circle()
                .strokeBorder(.secondary, lineWidth: 1.5)
                .frame(width: diameter, height: diameter)
                .overlay { Image(systemName: "plus").font(.caption2.weight(.heavy)).pestoQuiet() }
        }
    }
}
