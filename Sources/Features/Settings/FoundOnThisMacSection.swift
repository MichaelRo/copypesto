// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

/// The clipboard managers Pesto found installed, one row each. Pesto looked for them by name only: nothing of their
/// libraries is read until the person starts that app's import, which asks for Touch ID and a file first (ADR 0011). A
/// row starts the import through `AppState.pendingImportSource`, the same path the shelf banner takes.
struct FoundOnThisMacSection: View {
    @Environment(AppState.self) private var appState: AppState
    private var found: [ImportSource] {
        appState.installedImportSources
    }

    var body: some View {
        Group {
            if !found.isEmpty {
                Section {
                    card
                        .settingsRow("Found on this Mac")
                } header: {
                    Text("Found on this Mac")
                } footer: {
                    Text(
                        "Pesto looked for these apps by name only. It reads a library after you choose its file and " +
                            "confirm with Touch ID, and imports through the same rules as a copy."
                    )
                    .pestoCaption()
                }
            }
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            ForEach(found, id: \.self) { source in
                if source != found.first { Divider() }
                row(source)
            }
        }
    }

    private func row(_ source: ImportSource) -> some View {
        HStack(spacing: 12) {
            SourceAppIconView(bundleID: installedBundleID(source), appName: source.name, size: 32)
                .accessibilityHidden(true)
            Text(source.name)
            Spacer(minLength: 8)
            if let count = appState.importedThisSession[source] {
                Text("Imported \(count) clips")
                    .pestoCaption()
            } else {
                Button("Import\u{2026}") { start(source) }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Import from \(source.name)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { start(source) }
        .accessibilityIdentifier(AccessibilityID.foundOnThisMacRow(source.rawValue))
    }

    private func start(_ source: ImportSource) {
        appState.pendingImportSource = source
    }

    private func installedBundleID(_ source: ImportSource) -> String? {
        source.bundleIDs.first { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
            ?? source.bundleIDs.first
    }
}
