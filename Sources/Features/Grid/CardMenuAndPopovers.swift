// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

// MARK: - Menu sections that cost something

/// A context menu's content is built on every card update but a child view's body only runs when the menu is shown,
/// so work that is only needed to open the menu lives in views like these (card updates were paying for it).
struct EntityMenuSection: View {
    let text: String
    let onAction: (EntityDetector.Entity) -> Void

    var body: some View {
        let entities = EntityDetector.detect(in: text)
        if !entities.isEmpty {
            Section("Open With") {
                ForEach(entities.prefix(4).indices, id: \.self) { idx in
                    let entity = entities[idx]
                    Button {
                        onAction(entity)
                    } label: {
                        Label(entity.actionLabel, systemImage: entity.symbolName)
                    }
                }
            }
        }
    }
}

struct AIActionsMenuSection: View {
    let actions: [AIAction]
    let onAction: (AIAction) -> Void

    var body: some View {
        let availability = AIAvailability.current
        let supportsVision = AppleIntelligenceClient.supportsVision
        if availability.presentation != .hidden {
            Section(availability.isAvailable ? "AI Actions" : "AI Actions (\(availability.message))") {
                ForEach(actions, id: \.self) { action in
                    Button {
                        onAction(action)
                    } label: {
                        Label(action.rawValue, systemImage: action.symbolName)
                    }
                    .disabled(!action.isEnabled(availability: availability, supportsVision: supportsVision))
                }
            }
        }
    }
}

// MARK: - Note popover

struct NotePopover: View {
    @Binding var noteText: String
    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Note")
                .scaledFont(size: 12, weight: .semibold, maxScale: 1.3)
                .pestoQuiet()
            // Text size capped: the editor has a fixed 220x80 frame.
            TextEditor(text: $noteText)
                .scaledFont(size: 12, maxScale: 1.3)
                .frame(width: 220, height: 80)
                .scrollContentBackground(.hidden)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Spacer()
                Button("Save", action: onSave)
                    .buttonStyle(.pestoProminent)
                    .controlSize(.small)
            }
        }
        .padding(14)
    }
}

// MARK: - Tag popover

struct TagPopover: View {
    @Binding var tagText: String
    var onAdd: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("Tag name", text: $tagText)
                .frame(width: 150)
                .textFieldStyle(.roundedBorder)
                // Text size capped: the field has a fixed 150pt width.
                .scaledFont(size: 12, maxScale: 1.3)
                .onSubmit(onAdd)
            Button("Add", action: onAdd)
                .buttonStyle(.pestoProminent)
                .controlSize(.small)
                .disabled(tagText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(12)
    }
}
