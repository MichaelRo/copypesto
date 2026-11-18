// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import UIKit

struct ShareSheetView: View {
    let model: ShareModel

    private static let accent = Color(uiColor: UIColor { traits in
        let hex = traits.userInterfaceStyle == .dark ? BrandPalette.accentDark : BrandPalette.accentLight
        let value = UInt32(hex, radix: 16) ?? 0
        return UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: 1
        )
    })

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding()
                .navigationTitle("Save to Pesto")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { model.cancel() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { await model.save() } }
                            .disabled(!isReady)
                    }
                }
        }
        .tint(Self.accent)
    }

    private var isReady: Bool {
        if case .ready = model.phase { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .reading:
            ProgressView()
        case let .ready(preview):
            Text(preview)
                .lineLimit(1)
                .font(.body)
        case .saved:
            Label("Saved to Pesto", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Self.accent)
        case let .refused(message):
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}
