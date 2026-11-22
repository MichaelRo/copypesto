// SPDX-License-Identifier: MIT
import AuthenticationServices
import PestoCore
import SwiftUI
import UIKit

/// Guided setup checklist for iOS AutoFill and Pesto Keyboard.
struct QuickInsertSetupSheet: View {
    @Environment(MobileAppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var isAutoFillEnabled = false
    @State private var isKeyboardAdded = false
    @State private var autoFillStatusNote: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    statusRow(
                        title: String(localized: "AutoFill (Text Insertion)"),
                        subtitle: String(
                            localized: """
                            Insert recent, pinned, snippet, and collection clips in any text field \
                            (listed under AutoFill & Passwords in iOS Settings).
                            """
                        ),
                        isReady: isAutoFillEnabled
                    )
                    if isAutoFillEnabled {
                        Button("Open AutoFill Settings") {
                            Task {
                                await AutoFillSettings.openSettings()
                                await refreshStatus()
                            }
                        }
                    } else {
                        Button("Turn On AutoFill\u{2026}") {
                            AppDefaults.store.set(true, for: Setting.autoFillEnabled)
                            AppDefaults.store.set(true, for: Setting.quickInsertEnabled)
                            appState.quickInsertSettingChanged()
                            Task {
                                let granted = await ASSettingsHelper.requestToTurnOnCredentialProviderExtension()
                                autoFillStatusNote = granted
                                    ? String(localized: "AutoFill is enabled.")
                                    : String(
                                        localized:
                                        "Opened Settings. Turn on Pesto under AutoFill & Passwords."
                                    )
                                if !granted {
                                    await AutoFillSettings.openSettings()
                                }
                                await refreshStatus()
                            }
                        }
                    }
                    if let autoFillStatusNote {
                        Text(autoFillStatusNote)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    statusRow(
                        title: isKeyboardAdded
                            ? String(localized: "Pesto Keyboard (Added)")
                            : String(localized: "Pesto Keyboard"),
                        subtitle: isKeyboardAdded
                            ? String(
                                localized: """
                                Added in Keyboards. Make sure Allow Full Access is turned on in iOS Settings \
                                so Pesto can show your clips.
                                """
                            )
                            : String(
                                localized: """
                                Add Pesto in iOS Settings under General, Keyboard, Keyboards, and turn on \
                                Allow Full Access.
                                """
                            ),
                        isReady: isKeyboardAdded
                    )
                    Button("Open iOS Settings") {
                        openAppSettings()
                    }
                }
            }
            .navigationTitle("Set Up Keyboard & AutoFill")
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
