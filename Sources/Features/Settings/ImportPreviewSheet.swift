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

    private var importCount: Int {
        preview.importCount(includingHistory: importsHistory)
    }

    private func limitedSummary(_ plan: PasteImportPlan) -> String {
        if plan.lead(includingHistory: importsHistory) == .nothing {
            return String(
                localized: "None of \(CountText.clips(plan.libraryClips)) fit Keep clips for and Keep at most."
            )
        }
        let lead = switch plan.lead(includingHistory: importsHistory) {
        case .nothing: ""
        case let .pinboardsAndNewest(count): String(localized: "your collections and the newest \(count.formatted())")
        case .pinboards: String(localized: "your collections")
        case let .newest(count): String(localized: "the newest \(count.formatted())")
        case let .firstPinboards(count): String(localized: "the first \(count.formatted()) from your collections")
        }
        let chosen = plan.selectedCount(includingHistory: importsHistory).formatted()
        return String(localized: "\(chosen) of \(CountText.clips(plan.libraryClips)) will be imported: \(lead).")
    }

    private func pinnedLine(_ summary: String) -> String {
        let found = "Found \(CountText.clips(preview.pinnedCount)) pinned in \(preview.appName): \(summary). "
        return found + "They go into collections, and the clips are pinned."
    }

    @ViewBuilder
    private func limitCaptions(_ plan: PasteImportPlan) -> some View {
        if plan.historyLeftByRetention > 0, importsHistory {
            Text(
                "The rest are past Keep clips for and Keep at most. "
                    + "Raise those in Settings \u{2192} Data to bring in more."
            )
            .pestoCaption()
        }
        if plan.historyLeftByCap + plan.pinboardsLeftByCap > 0 {
            let limit = ImportCap.paste.maxClips.formatted() + " clips"
            let size = ByteCountFormatter.string(fromByteCount: Int64(ImportCap.paste.maxBytes), countStyle: .decimal)
            Text("Pesto imports at most \(limit) or \(size) at a time.")
                .pestoCaption()
        }
        if plan.displacedExisting > 0, importsHistory {
            Text("\(plan.displacedExisting.formatted()) of your older Pesto clips will go to make room.")
                .pestoCaption()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import from \(preview.appName)")
                .font(.title3.weight(.semibold))
            if let plan = preview.plan, plan.isLimited {
                Text(limitedSummary(plan))
                    .accessibilityIdentifier(AccessibilityID.importPreviewLimits)
                limitCaptions(plan)
            }
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
            if let plan = preview.plan, plan.alreadyInPesto > 0 {
                Text("\(plan.alreadyInPesto.formatted()) are already in Pesto and will be skipped.")
                    .pestoCaption()
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
                    .disabled(importCount == 0)
                    .accessibilityIdentifier(AccessibilityID.importPasteConfirm)
            }
        }
        .padding(20)
        .frame(width: 420)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.importPreviewSheet)
    }
}
