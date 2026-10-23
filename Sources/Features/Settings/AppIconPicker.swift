// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The app icons as buttons. The choice is shown in the Dock and the app switcher while a Pesto window is open.
struct AppIconPicker: View {
    @Binding var selection: String
    @Environment(\.pestoAccent) private var accent

    var body: some View {
        HStack(spacing: 14) {
            ForEach(AppIconChoice.allCases, id: \.self) { choice in
                let isSelected = AppIconChoice(stored: selection) == choice
                Button {
                    selection = choice.rawValue
                } label: {
                    VStack(spacing: 0) {
                        Image(choice.previewImageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                            .padding(3)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(isSelected ? accent : Color.clear, lineWidth: 2)
                            )
                    }
                }
                .buttonStyle(.plain)
                .help(
                    "\(choice.displayName): shown in the Dock and the Command-Tab switcher while a Pesto window is open"
                )
                .selectableTile("\(choice.displayName) icon", isSelected: isSelected) { selection = choice.rawValue }
                .accessibilityIdentifier(AccessibilityID.settingsChoice("appIcon", choice.rawValue))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("App icon")
    }
}
