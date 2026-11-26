// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// Settings inside the keyboard (ADR 0066), opened from the Pesto chip at the end of the chip row: the card size,
/// chosen while seeing the cards at that size (the keyboard resizes with it), and the way to the rest in Pesto.
struct KeyboardSettingsPanel: View {
    let size: KeyboardSize
    let sample: [QuickInsertEntry]
    let setSize: (KeyboardSize) -> Void
    let openSettings: (() -> Void)?
    let close: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: close) {
                    Label("Clips", systemImage: "chevron.backward")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Pesto Keyboard").font(.subheadline.weight(.bold))
                Spacer()
                if let openSettings {
                    Button("More", action: openSettings)
                        .font(.subheadline)
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                        .accessibilityLabel(Text("Open Pesto Settings"))
                }
            }
            if openSettings == nil {
                Text("More settings are in Pesto: Settings → Keyboard & AutoFill.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Picker("Size", selection: Binding(get: { size }, set: setSize)) {
                ForEach(KeyboardSize.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    let cardSize = KeyboardLayout.cardSize(size: size, isRegular: sizeClass == .regular)
                    ForEach(sample.prefix(4)) { entry in
                        KeyboardClipKey(entry: entry, cardSize: cardSize, feedback: nil)
                            .allowsHitTesting(false)
                    }
                }
            }
            .accessibilityHidden(true)
            .scrollEdgeEffectHidden(true, for: .all)
            Text("Cards are shown at this size. Settings in Pesto choose what the keyboard shows.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
