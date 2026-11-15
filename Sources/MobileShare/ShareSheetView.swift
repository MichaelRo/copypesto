// SPDX-License-Identifier: MIT
import SwiftUI

struct ShareSheetView: View {
    let model: ShareModel

    private static let accent = BrandAccent.color

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
