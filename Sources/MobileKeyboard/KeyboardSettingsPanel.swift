// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// Settings inside the keyboard (ADR 0066), opened from the gear chip at the end of the chip row: the card size,
/// chosen while seeing the person's own cards at that size and in as many rows as the keyboard will show (the keyboard
/// resizes with it), and the way to the rest in Pesto.
struct KeyboardSettingsPanel: View {
    let size: KeyboardSize
    let sample: [QuickInsertEntry]
    let theme: WidgetSnapshot.Theme
    let appIcons: [String: Data]
    let setSize: (KeyboardSize) -> Void
    let openSettings: (() -> Void)?
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
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
            KeyboardSizePreview(
                size: size, entries: Array(sample.prefix(8)), theme: theme, appIcons: appIcons,
                picture: { entry in
                    entry.thumbnail
                        .flatMap { KeyboardThumbnails.shared.picture(for: entry.id, data: $0) }
                        .map { ($0.image, $0.backdrop) }
                }
            )
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        ZStack {
            Text("Keyboard Settings")
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button(action: close) {
                    Label("Clips", systemImage: "chevron.backward")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                Spacer()
                if let openSettings {
                    Button(action: openSettings) {
                        Label("Open Pesto", systemImage: "arrow.up.forward.app")
                            .labelStyle(.iconOnly)
                            .font(.body)
                            .frame(minWidth: 30, minHeight: 30)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .accessibilityLabel(Text("Open Pesto Settings"))
                }
            }
        }
        .frame(height: 30)
    }
}
