// SPDX-License-Identifier: MIT
import AuthenticationServices
import PestoCore
import SwiftUI
import UIKit

/// Guided setup checklist for iOS AutoFill, Pesto Keyboard, and Paste permission.
struct QuickInsertSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var isAutoFillEnabled = false
    @State private var isKeyboardAdded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    statusRow(
                        title: String(localized: "AutoFill (Text Insertion)"),
                        subtitle: String(
                            localized: "Insert pinned clips and snippets in any text field via AutoFill."
                        ),
                        isReady: isAutoFillEnabled
                    )
                    Button("Turn On AutoFill\u{2026}") {
                        AppDefaults.store.set(true, for: Setting.autoFillEnabled)
                        AppDefaults.store.set(true, for: Setting.quickInsertEnabled)
                        Task {
                            await AutoFillSettings.open()
                            await refreshStatus()
                        }
                    }
                }

                Section {
                    statusRow(
                        title: String(localized: "Pesto Keyboard"),
                        subtitle: String(
                            localized: "Add Pesto in Settings > General > Keyboard > Keyboards and allow Full Access."
                        ),
                        isReady: isKeyboardAdded
                    )
                    Button("Open Keyboard Settings") {
                        openAppSettings()
                    }
                }

                Section {
                    statusRow(
                        title: String(localized: "Paste Without Asking"),
                        subtitle: String(
                            localized: "Set Paste from Other Apps to Allow so Pesto doesn\u{2019}t prompt every time."
                        ),
                        isReady: nil
                    )
                    Button("Open Pesto Settings") {
                        _ = AppPasteboard.general.hasStrings
                        openAppSettings()
                    }
                }
            }
            .navigationTitle("Set Up Quick Insert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await refreshStatus() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await refreshStatus() }
                }
            }
        }
    }

    private func statusRow(title: String, subtitle: String, isReady: Bool?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let isReady {
                Image(systemName: isReady ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isReady ? Color.statusGood : Color.secondary)
                    .font(.title3)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "doc.on.clipboard")
                    .foregroundStyle(.secondary)
                    .font(.title3)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func refreshStatus() async {
        let state = await ASCredentialIdentityStore.shared.state()
        isAutoFillEnabled = state.isEnabled
        isKeyboardAdded = UITextInputMode.activeInputModes.contains { mode in
            (mode.value(forKey: "identifier") as? String)?.contains("net.copypesto.pesto") == true
        }
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}
