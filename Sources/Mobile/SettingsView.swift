// SPDX-License-Identifier: MIT
import LocalAuthentication
import PestoCore
import SwiftUI

/// The few settings the iOS app has. What only a Mac does (shortcuts, the login item, app exclusions) is not here.
struct SettingsView: View {
    @Environment(MobileAppState.self) private var appState
    @AppStorage(Setting.appTheme) private var theme: String
    @AppStorage(Setting.appearanceMode) private var appearance: String
    @AppStorage(Setting.authenticationGraceMinutes) private var graceMinutes: Int
    @State private var clearCount = 0
    @State private var isConfirmingClear = false

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    ForEach(AppTheme.allCases, id: \.rawValue) { choice in
                        Text(choice.displayName).tag(choice.rawValue)
                    }
                }
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
            }
            Section {
                Picker(Self.graceLabel, selection: $graceMinutes) {
                    ForEach(AuthenticationGrace.choices, id: \.self) { minutes in
                        Text(Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes])))
                            .tag(minutes)
                    }
                }
            } header: {
                Text("Privacy")
            } footer: {
                Text("Hidden clips stay masked until you show them. Copying one never shows it.")
            }
            Section {
                NavigationLink("Sync") { SyncSettingsView() }
            }
            Section {
                Button("Clear History", role: .destructive) { Task { await askToClear() } }
            } footer: {
                Text("Pinned clips are kept.")
            }
            Section {
                LabeledContent("Pesto", value: AppVersion.displayString())
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            String(localized: "Clear \(clearCount) clips?"), isPresented: $isConfirmingClear, titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) { Task { await appState.clearHistory() } }
        } message: {
            Text("This deletes every clip that is not pinned. It can\u{2019}t be undone.")
        }
    }

    private func askToClear() async {
        clearCount = await appState.nonPinnedCount()
        if clearCount > 0 {
            isConfirmingClear = true
        } else {
            appState.tell(String(localized: "There is nothing to clear."))
        }
    }

    private static var graceLabel: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return switch context.biometryType {
        case .faceID: String(localized: "Ask for Face ID again after")
        case .touchID: String(localized: "Ask for Touch ID again after")
        case .opticID: String(localized: "Ask for Optic ID again after")
        default: String(localized: "Ask for the passcode again after")
        }
    }
}

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pestoSurface) private var ground

    var body: some View {
        NavigationStack {
            SettingsView()
                .scrollContentBackground(.hidden)
                .background(ground.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
