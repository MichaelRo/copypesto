// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// What is about to come in from another app, shown before anything is imported (Paste, Maccy and Alfred alike).
struct ImportPreviewSheet: View {
    let preview: ImportPreview
    let retention: RetentionPolicy
    let onCancel: () -> Void
    let onImport: (Bool) -> Void
    @State private var includeHistory: Bool

    init(
        preview: ImportPreview, retention: RetentionPolicy,
        onCancel: @escaping () -> Void, onImport: @escaping (Bool) -> Void
    ) {
        self.preview = preview
        self.retention = retention
        self.onCancel = onCancel
        self.onImport = onImport
        // With no pins there is nothing else to import, so history is in from the start.
        _includeHistory = State(initialValue: !preview.hasPins)
    }

    private var importsHistory: Bool {
        includeHistory || !preview.hasPins
    }

    private var expiring: Int {
        preview.expiring(retention: retention, includingHistory: importsHistory)
    }

    private func pinnedLine(_ summary: String) -> String {
        let found = "Found \(CountText.clips(preview.pinnedCount)) pinned in \(preview.appName): \(summary). "
        return found + "They go into collections, and the clips are pinned."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import from \(preview.appName)")
                .font(.title3.weight(.semibold))
            if preview.hasPins, let summary = preview.pinSummary {
                Text(pinnedLine(summary))
            }
            if preview.historyCount > 0 {
                if preview.hasPins {
                    Toggle(
                        "Also import clipboard history (\(CountText.clips(preview.historyCount)))",
                        isOn: $includeHistory
                    )
                    .accessibilityIdentifier(AccessibilityID.importPreviewHistoryToggle)
                } else {
                    Text("Found \(CountText.clips(preview.historyCount)) of clipboard history.")
                }
                if importsHistory {
                    Text("History clips are not pinned, so your retention setting may remove the older ones.")
                        .pestoCaption()
                }
            }
            if expiring > 0 {
                Text("\(expiring) of them are older than Keep clips for allows and go.")
                    .pestoCaption()
                    .accessibilityIdentifier(AccessibilityID.importPreviewExpiring)
            }
            if preview.skipped > 0 {
                Text("\(preview.skipped) clips cannot be imported (pictures or empty).")
                    .pestoCaption()
            }
            Text(
                "Pesto reads a copy of the \(preview.appName) library. \(preview.appName) is not changed, "
                    + "and clips you have are skipped."
            )
            .pestoCaption()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier(AccessibilityID.importPreviewCancel)
                Button("Import") { onImport(importsHistory) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(preview.records(includingHistory: importsHistory).isEmpty)
                    .accessibilityIdentifier(AccessibilityID.importPasteConfirm)
            }
        }
        .padding(20)
        .frame(width: 420)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.importPreviewSheet)
    }
}
